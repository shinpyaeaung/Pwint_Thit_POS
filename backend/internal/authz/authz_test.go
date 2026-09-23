package authz_test

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
)

func TestPermissionsIntegration(t *testing.T) {
	conn := testutil.Database(t)
	ctx := context.Background()
	if err := migrate.Up(ctx, conn, os.DirFS("../../../database/migrations")); err != nil {
		t.Fatal(err)
	}
	for _, sql := range []string{
		`INSERT INTO app.users(id,username,display_name,password_hash,role_code) VALUES('00000000-0000-0000-0000-000000000001','owner','Owner','not-a-real-password-hash','SUPER_ADMIN'),('00000000-0000-0000-0000-000000000002','staff','Staff','not-a-real-password-hash','STAFF_ADMIN')`,
	} {
		if _, err := conn.Exec(ctx, sql); err != nil {
			t.Fatal(err)
		}
	}
	tokens := []string{base64.RawURLEncoding.EncodeToString(make([]byte, 32)), base64.RawURLEncoding.EncodeToString([]byte("12345678901234567890123456789012"))}
	for i, token := range tokens {
		hash := sha256.Sum256([]byte(token))
		id := "00000000-0000-0000-0000-000000000001"
		if i == 1 {
			id = "00000000-0000-0000-0000-000000000002"
		}
		if _, err := conn.Exec(ctx, `INSERT INTO app.user_sessions(user_id,token_hash,expires_at) VALUES($1,$2,now()+interval '1 hour')`, id, hash[:]); err != nil {
			t.Fatal(err)
		}
	}
	q := database.New(conn)
	r := httpapi.New(q, slog.New(slog.NewJSONHandler(io.Discard, nil)), authz.New(q))
	request := func(token string, want int) {
		t.Helper()
		w := httptest.NewRecorder()
		req := httptest.NewRequest("GET", "/api/v1/permissions", nil)
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		req.Header.Set("X-Role", "SUPER_ADMIN")
		req.Header.Set("X-User-ID", "00000000-0000-0000-0000-000000000001")
		r.ServeHTTP(w, req)
		if w.Code != want {
			t.Fatalf("status=%d want=%d body=%s", w.Code, want, w.Body.String())
		}
	}
	run := func(sql string) {
		t.Helper()
		if _, err := conn.Exec(ctx, sql); err != nil {
			t.Fatal(err)
		}
	}
	request("", 401)
	request("forged", 401)
	request(tokens[0], 200)
	request(tokens[1], 403)
	run(`INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002','permissions.manage','00000000-0000-0000-0000-000000000001')`)
	request(tokens[1], 200)
	run(`DELETE FROM app.user_permissions`)
	request(tokens[1], 403)
	run(`UPDATE app.users SET is_active=false WHERE username='owner'`)
	request(tokens[0], 401)
	run(`UPDATE app.users SET is_active=true WHERE username='owner'; UPDATE app.user_sessions SET revoked_at=now() WHERE user_id='00000000-0000-0000-0000-000000000001'`)
	request(tokens[0], 401)
	run(`UPDATE app.user_sessions SET expires_at=created_at+interval '1 microsecond' WHERE user_id='00000000-0000-0000-0000-000000000002'`)
	request(tokens[1], 401)
}

type unavailable struct{}

func (unavailable) AuthenticateSession(context.Context, []byte) (database.AuthenticateSessionRow, error) {
	return database.AuthenticateSessionRow{}, errors.New("private database details")
}
func (unavailable) HasPermission(context.Context, database.HasPermissionParams) (bool, error) {
	return false, errors.New("unavailable")
}
func (unavailable) ListPermissions(context.Context) ([]database.ListPermissionsRow, error) {
	return nil, errors.New("unavailable")
}
func TestAuthorizationFailsClosed(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, service := range []*authz.Service{nil, authz.New(unavailable{})} {
		r := gin.New()
		r.GET("/protected", service.Require("permissions.manage"), func(c *gin.Context) { t.Error("protected handler executed") })
		w := httptest.NewRecorder()
		req := httptest.NewRequest("GET", "/protected", nil)
		req.Header.Set("Authorization", "Bearer "+base64.RawURLEncoding.EncodeToString(make([]byte, 32)))
		r.ServeHTTP(w, req)
		if w.Code != 503 {
			t.Fatalf("status=%d", w.Code)
		}
	}
}
