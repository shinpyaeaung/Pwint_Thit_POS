package authn_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/password"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
)

func TestAuthenticationIntegration(t *testing.T) {
	gin.SetMode(gin.TestMode)
	conn := testutil.Database(t)
	ctx := context.Background()
	if err := migrate.Up(ctx, conn, os.DirFS("../../../database/migrations")); err != nil {
		t.Fatal(err)
	}
	hash, err := password.Hash("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = conn.Exec(ctx, `INSERT INTO app.users(id,username,display_name,password_hash,role_code) VALUES('00000000-0000-0000-0000-000000000001','owner','Owner',$1,'SUPER_ADMIN'),('00000000-0000-0000-0000-000000000002','staff','Staff',$1,'STAFF_ADMIN')`, hash); err != nil {
		t.Fatal(err)
	}
	q := database.New(conn)
	router := httpapi.New(q, slog.New(slog.NewJSONHandler(io.Discard, nil)), authz.New(q), authn.New(conn, authn.Options{SecureCookie: true, AllowedOrigins: []string{"https://app.test"}}))
	request := func(method, path, body string, cookie *http.Cookie, origin string, want int) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Pwint-Thit-Request", "1")
		r.Header.Set("Origin", origin)
		r.Header.Set("X-Role", "SUPER_ADMIN")
		if cookie != nil {
			r.AddCookie(cookie)
		}
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		if w.Code != want {
			t.Fatalf("%s %s status=%d want=%d body=%s", method, path, w.Code, want, w.Body.String())
		}
		return w
	}
	login := func(user string) *http.Cookie {
		t.Helper()
		w := request("POST", "/api/v1/auth/login", `{"username":"`+user+`","password":"correct horse battery staple"}`, nil, "https://app.test", 200)
		cookies := w.Result().Cookies()
		if len(cookies) != 1 || !cookies[0].HttpOnly || !cookies[0].Secure || cookies[0].SameSite != http.SameSiteStrictMode || cookies[0].Path != "/api/v1" {
			t.Fatalf("insecure cookie: %+v", cookies)
		}
		return cookies[0]
	}
	request("GET", "/api/v1/auth/me", "", nil, "", 401)
	request("POST", "/api/v1/auth/login", `{"username":"owner","password":"wrong"}`, nil, "https://evil.test", 403)
	request("POST", "/api/v1/auth/login", `{"username":"owner","password":"wrong"}`, nil, "https://app.test", 401)
	request("POST", "/api/v1/auth/login", `{"username":"missing","password":"wrong"}`, nil, "https://app.test", 401)
	owner := login("owner")
	staff := login("staff")
	me := request("GET", "/api/v1/auth/me", "", owner, "", 200)
	if strings.Contains(me.Body.String(), "password_hash") || strings.Contains(me.Body.String(), owner.Value) {
		t.Fatal("authentication secret leaked")
	}
	request("GET", "/api/v1/permissions", "", staff, "", 403)
	request("GET", "/api/v1/users", "", staff, "", 403)
	request("PUT", "/api/v1/users/00000000-0000-0000-0000-000000000002/permissions", `{"permissions":["users.manage","products.view"]}`, owner, "https://app.test", 204)
	request("GET", "/api/v1/users", "", staff, "", 200)
	current := request("GET", "/api/v1/auth/me", "", staff, "", 200)
	if !strings.Contains(current.Body.String(), "products.view") {
		t.Fatal("grants missing from current user")
	}
	request("PUT", "/api/v1/users/00000000-0000-0000-0000-000000000002/permissions", `{"permissions":["permissions.manage"]}`, staff, "https://app.test", 403)
	request("PUT", "/api/v1/users/00000000-0000-0000-0000-000000000002/permissions", `{"permissions":["unknown.permission"]}`, owner, "https://app.test", 400)
	request("GET", "/api/v1/users", "", staff, "", 200) // failed update must roll back
	request("PUT", "/api/v1/users/00000000-0000-0000-0000-000000000002/permissions", `{"permissions":[]}`, owner, "https://app.test", 204)
	request("GET", "/api/v1/users", "", staff, "", 403)
	created := request("POST", "/api/v1/users", `{"username":"newstaff","display_name":"New staff","password":"another long password"}`, owner, "https://app.test", 201)
	var data map[string]any
	if err = json.Unmarshal(created.Body.Bytes(), &data); err != nil {
		t.Fatal(err)
	}
	newstaff := login("owner")
	if newstaff.Value == owner.Value {
		t.Fatal("reused session token")
	}
	request("POST", "/api/v1/auth/logout", "{}", staff, "https://evil.test", 403)
	request("GET", "/api/v1/auth/me", "", staff, "", 200)
	cleared := request("POST", "/api/v1/auth/logout", "{}", staff, "https://app.test", 204)
	if cleared.Result().Cookies()[0].MaxAge != -1 {
		t.Fatal("cookie not cleared")
	}
	request("GET", "/api/v1/auth/me", "", staff, "", 401)
	request("POST", "/api/v1/auth/logout", "{}", staff, "https://app.test", 204)
	expired := login("staff")
	if _, err = conn.Exec(ctx, `UPDATE app.user_sessions SET expires_at=created_at+interval '1 microsecond' WHERE user_id='00000000-0000-0000-0000-000000000002'`); err != nil {
		t.Fatal(err)
	}
	request("GET", "/api/v1/auth/me", "", expired, "", 401)
	changed := login("staff")
	if _, err = conn.Exec(ctx, `UPDATE app.users SET password_changed_at=clock_timestamp() WHERE username='staff'`); err != nil {
		t.Fatal(err)
	}
	request("GET", "/api/v1/auth/me", "", changed, "", 401)
	if _, err = conn.Exec(ctx, `UPDATE app.users SET is_active=false WHERE username='staff'`); err != nil {
		t.Fatal(err)
	}
	request("POST", "/api/v1/auth/login", `{"username":"staff","password":"correct horse battery staple"}`, nil, "https://app.test", 401)
	var sessions, logs int
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.user_sessions WHERE octet_length(token_hash)=32`).Scan(&sessions); err != nil || sessions == 0 {
		t.Fatal("no hashed sessions")
	}
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.audit_logs WHERE action='permissions.replace'`).Scan(&logs); err != nil || logs != 2 {
		t.Fatalf("audit=%d %v", logs, err)
	}
	for i := 0; i < 10; i++ {
		request("POST", "/api/v1/auth/login", `{"username":"ratelimited","password":"wrong"}`, nil, "https://app.test", 401)
	}
	request("POST", "/api/v1/auth/login", `{"username":"ratelimited","password":"wrong"}`, nil, "https://app.test", 429)
}
