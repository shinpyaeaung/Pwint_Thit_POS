package suppliers_test

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/suppliers"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestSupplierIntegration(t *testing.T) {
	gin.SetMode(gin.TestMode)
	ctx := context.Background()
	conn := testutil.Database(t)
	if err := migrate.Up(ctx, conn, os.DirFS("../../../database/migrations")); err != nil {
		t.Fatal(err)
	}
	cfg, err := pgxpool.ParseConfig(conn.Config().ConnString())
	if err != nil {
		t.Fatal(err)
	}
	cfg.ConnConfig.Database = conn.Config().Database
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	const owner = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	const staff = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA"
	for i, token := range []string{owner, staff} {
		role := "SUPER_ADMIN"
		name := "owner"
		if i == 1 {
			role = "STAFF_ADMIN"
			name = "staff"
		}
		h := sha256.Sum256([]byte(token))
		_, err = conn.Exec(ctx, `WITH u AS (INSERT INTO app.users(username,display_name,password_hash,role_code) VALUES($1,$1,'test-only-placeholder-hash',$2) RETURNING id) INSERT INTO app.user_sessions(user_id,token_hash,expires_at) SELECT id,$3,now()+interval '1 hour' FROM u`, name, role, h[:])
		if err != nil {
			t.Fatal(err)
		}
	}
	q := database.New(pool)
	a := authz.New(q)
	r := httpapi.New(q, slog.New(slog.NewJSONHandler(io.Discard, nil)), a, authn.New(pool, authn.Options{AllowedOrigins: []string{"http://app.test"}}))
	suppliers.New(pool).Register(r, a)
	raw := func(method, path string, body any, token string) *httptest.ResponseRecorder {
		data, _ := json.Marshal(body)
		req := httptest.NewRequest(method, "/api/v1"+path, strings.NewReader(string(data)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Origin", "http://app.test")
		req.Header.Set("X-Pwint-Thit-Request", "1")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w
	}
	call := func(method, path string, body any, token string, want int) map[string]any {
		t.Helper()
		w := raw(method, path, body, token)
		if w.Code != want {
			t.Fatalf("%s %s got %d want %d: %s", method, path, w.Code, want, w.Body.String())
		}
		v := map[string]any{}
		if w.Code != 204 {
			if err := json.Unmarshal(w.Body.Bytes(), &v); err != nil {
				t.Fatal(err)
			}
		}
		return v
	}

	input := func(code string) map[string]any {
		return map[string]any{"code": code, "name": "Golden Supply", "contact_person": "Daw May", "phone": "+95 09123456", "address": "Mandalay", "country_code": "mm", "supplier_type": "Wholesale", "payment_terms": "Net 30 days", "notes": "Call before delivery", "is_active": true}
	}
	call("GET", "/suppliers", nil, "", 401)
	call("GET", "/suppliers", nil, staff, 403)
	call("POST", "/suppliers", input("NO"), staff, 403)
	body := input("SUP-001")
	p := call("POST", "/suppliers", body, owner, 201)
	id := p["id"].(string)
	if p["country_code"] != "MM" || p["phone"] != "+95 09123456" {
		t.Fatal("contact fields changed")
	}
	call("POST", "/suppliers", input("sup-001"), owner, 409)
	bad := input("BAD")
	bad["country_code"] = "Myanmar"
	call("POST", "/suppliers", bad, owner, 400)
	bad = input("BAD")
	bad["name"] = " "
	call("POST", "/suppliers", bad, owner, 400)
	bad = input("BAD")
	bad["unexpected"] = "x"
	call("POST", "/suppliers", bad, owner, 400)
	call("GET", "/suppliers?page=0", nil, owner, 400)
	call("GET", "/suppliers?page_size=101", nil, owner, 400)
	call("GET", "/suppliers?country=Myanmar", nil, owner, 400)
	call("GET", "/suppliers/no-id", nil, owner, 400)
	call("GET", "/suppliers/00000000-0000-0000-0000-000000000000", nil, owner, 404)
	for _, filter := range []string{"q=golden", "q=Daw", "q=09123456", "q=sup-001", "country=MM&status=active"} {
		if got := call("GET", "/suppliers?"+filter, nil, owner, 200); got["total"] != float64(1) {
			t.Fatal("search/filter", filter, got)
		}
	}
	second := call("POST", "/suppliers", input("SUP-002"), owner, 201)
	if got := call("GET", "/suppliers?page_size=1&page=2", nil, owner, 200); got["total"] != float64(2) || len(got["suppliers"].([]any)) != 1 {
		t.Fatal("pagination", got)
	}
	body["version"] = p["version"]
	body["name"] = "Golden renamed"
	body["is_active"] = false
	p = call("PUT", "/suppliers/"+id, body, owner, 200)
	call("PUT", "/suppliers/"+id, body, owner, 409)
	call("DELETE", "/suppliers/"+id, map[string]any{"version": "1"}, owner, 409)
	if got := call("GET", "/suppliers?status=inactive", nil, owner, 200); got["total"] != float64(1) {
		t.Fatal("status")
	}
	// Isolate purchase history by supplier, preserve all statuses and exact original-currency totals.
	_, err = conn.Exec(ctx, `WITH product AS (INSERT INTO app.products(sku,name,base_unit_code) VALUES('HISTORY','History item','PIECE') RETURNING id), purchase AS (INSERT INTO app.purchases(purchase_number,supplier_id,purchased_at,currency_code,mmk_per_unit,created_by) SELECT 'PO-EXACT',$1,now(),'MMK',1,id FROM app.users WHERE username='owner' RETURNING id) INSERT INTO app.purchase_items(purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original) SELECT purchase.id,1,product.id,'PIECE',3,1,123456789.123456 FROM purchase CROSS JOIN product`, id)
	if err != nil {
		t.Fatal(err)
	}
	if other := call("GET", "/suppliers/"+second["id"].(string)+"/purchases", nil, owner, 200); other["total"] != float64(0) {
		t.Fatal("cross-supplier history leaked")
	}
	history := call("GET", "/suppliers/"+id+"/purchases", nil, owner, 200)
	if history["total"] != float64(1) || history["purchases"].([]any)[0].(map[string]any)["total_original"] != "370370367.3704" {
		t.Fatal("exact history", history)
	}
	call("GET", "/suppliers/00000000-0000-0000-0000-000000000000/purchases", nil, owner, 404)
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,'suppliers.view',o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner'`)
	if err != nil {
		t.Fatal(err)
	}
	call("GET", "/suppliers/"+id, nil, staff, 200)
	call("GET", "/suppliers/"+id+"/purchases", nil, staff, 403)
	call("PUT", "/suppliers/"+id, body, staff, 403)
	call("DELETE", "/suppliers/"+id, map[string]any{"version": p["version"]}, staff, 403)
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,'purchases.view',o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner'`)
	if err != nil {
		t.Fatal(err)
	}
	history = call("GET", "/suppliers/"+id+"/purchases", nil, staff, 200)
	row := history["purchases"].([]any)[0].(map[string]any)
	if _, exposed := row["total_original"]; exposed || history["can_view_cost"] != false {
		t.Fatal("cost exposure", history)
	}
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,'purchases.view_cost',o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner'`)
	if err != nil {
		t.Fatal(err)
	}
	history = call("GET", "/suppliers/"+id+"/purchases", nil, staff, 200)
	if history["can_view_cost"] != true {
		t.Fatal("cost grant ignored")
	}
	call("DELETE", "/suppliers/"+id, map[string]any{"version": p["version"]}, owner, 204)
	call("GET", "/suppliers/"+id+"/purchases", nil, owner, 200)
	call("GET", "/suppliers/"+id, nil, owner, 200)
	if got := call("GET", "/suppliers?status=archived", nil, owner, 200); got["total"] != float64(1) {
		t.Fatal("archive")
	}
	if got := call("GET", "/suppliers?q=SUP-001", nil, owner, 200); got["total"] != float64(0) {
		t.Fatal("archive in current")
	}
	call("POST", "/suppliers", input("SUP-001"), owner, 409)
	body["version"] = "3"
	call("PUT", "/suppliers/"+id, body, owner, 409)
	var audits int
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.audit_logs WHERE entity_type='suppliers' AND entity_id=$1`, id).Scan(&audits); err != nil || audits != 3 {
		t.Fatal("audit", audits, err)
	}
}
