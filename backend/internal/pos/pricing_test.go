package pos_test

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/pos"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
)

func TestLandedPricingIntegration(t *testing.T) {
	gin.SetMode(gin.TestMode)
	ctx := context.Background()
	conn := testutil.Database(t)
	if e := migrate.Up(ctx, conn, os.DirFS("../../../database/migrations")); e != nil {
		t.Fatal(e)
	}
	fixture, e := os.ReadFile("../../../database/tests/fixture.sql")
	if e != nil {
		t.Fatal(e)
	}
	if _, e = conn.Exec(ctx, string(fixture)); e != nil {
		t.Fatal(e)
	}
	cfg, e := pgxpool.ParseConfig(conn.Config().ConnString())
	if e != nil {
		t.Fatal(e)
	}
	cfg.ConnConfig.Database = conn.Config().Database
	pool, e := pgxpool.NewWithConfig(ctx, cfg)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	const owner = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	const staff = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA"
	for i, token := range []string{owner, staff} {
		h := sha256.Sum256([]byte(token))
		name := []string{"owner", "staff"}[i]
		if _, e = conn.Exec(ctx, `INSERT INTO app.user_sessions(user_id,token_hash,expires_at) SELECT id,$1,now()+interval '1 hour' FROM app.users WHERE username=$2`, h[:], name); e != nil {
			t.Fatal(e)
		}
	}
	q := database.New(pool)
	a := authz.New(q)
	r := httpapi.New(q, slog.New(slog.NewJSONHandler(io.Discard, nil)), a, authn.New(pool, authn.Options{AllowedOrigins: []string{"http://app.test"}}))
	pos.New(pool).Register(r, a)
	raw := func(method, path string, body any, token string) *httptest.ResponseRecorder {
		d, _ := json.Marshal(body)
		req := httptest.NewRequest(method, "/api/v1"+path, strings.NewReader(string(d)))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Origin", "http://app.test")
		req.Header.Set("X-Pwint-Thit-Request", "1")
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		r.ServeHTTP(w, req)
		return w
	}
	call := func(method, path string, body any, token string, want int) map[string]any {
		t.Helper()
		w := raw(method, path, body, token)
		if w.Code != want {
			t.Fatalf("%s %s: %d %s", method, path, w.Code, w.Body.String())
		}
		v := map[string]any{}
		if want != 204 {
			if e := json.Unmarshal(w.Body.Bytes(), &v); e != nil {
				t.Fatal(e)
			}
		}
		return v
	}
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, e := conn.Exec(ctx, sql, args...); e != nil {
			t.Fatal(e)
		}
	}

	const product = "00000000-0000-0000-0000-000000000020"
	const warehouse = "00000000-0000-0000-0000-000000000012"
	const item = "00000000-0000-0000-0000-000000000051"
	path := "/pos/pricing-costs?warehouse_id=" + warehouse + "&product_id=" + product
	if w := raw("GET", path, nil, owner); w.Code != 200 || strings.TrimSpace(w.Body.String()) != "[]" {
		t.Fatal(w.Code, w.Body.String())
	}
	call("GET", path, nil, staff, 403)
	exec(`INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002','products.update','00000000-0000-0000-0000-000000000001')`)
	call("GET", path, nil, staff, 403) // price permission alone cannot expose costs
	exec(`INSERT INTO app.product_units(product_id,unit_code,units_per_pack) VALUES($1,'BOTTLE',1)`, product)
	body := map[string]any{"product_id": product, "warehouse_id": warehouse, "shipment_item_id": item, "unit_code": "CARTON", "version": "1", "mode": "PER_UNIT", "retail_value": "21000", "wholesale_value": "20500"}
	call("PUT", "/pos/landed-prices", body, owner, 409) // no unfinalized estimates
	exec(`UPDATE app.shipment_items SET purchase_cost_mmk=220000,allocated_transport_mmk=20000,costing_sellable_quantity=12 WHERE id=$1`, item)
	exec(`UPDATE app.shipments SET costs_finalized_at=now(),costs_finalized_by='00000000-0000-0000-0000-000000000001' WHERE id='00000000-0000-0000-0000-000000000050'`)
	var costs []map[string]any
	w := raw("GET", path, nil, owner)
	if e = json.Unmarshal(w.Body.Bytes(), &costs); e != nil || len(costs) != 1 || costs[0]["landed_cost_mmk"] != "240000.0000" || costs[0]["cargo_cost_mmk"] != "20000.0000" {
		t.Fatal(w.Body.String(), e)
	}
	call("PUT", "/pos/landed-prices", body, staff, 403)
	call("PUT", "/pos/landed-prices", body, owner, 204)
	call("PUT", "/pos/landed-prices", body, owner, 409) // stale version cannot overwrite
	check := func(wantBottle, wantCarton string) {
		t.Helper()
		var bottle, carton string
		if e := conn.QueryRow(ctx, `SELECT retail_price_mmk::text FROM app.warehouse_prices WHERE product_id=$1 AND warehouse_id=$2 AND unit_code='BOTTLE'`, product, warehouse).Scan(&bottle); e != nil {
			t.Fatal(e)
		}
		if e := conn.QueryRow(ctx, `SELECT retail_price_mmk::text FROM app.warehouse_prices WHERE product_id=$1 AND warehouse_id=$2 AND unit_code='CARTON'`, product, warehouse).Scan(&carton); e != nil {
			t.Fatal(e)
		}
		if bottle != wantBottle || carton != wantCarton {
			t.Fatalf("prices %s %s", bottle, carton)
		}
	}
	check("21000.0000", "252000.0000")
	body["version"] = "2"
	body["mode"] = "MARKUP"
	body["retail_value"] = "5"
	body["wholesale_value"] = "2.5"
	call("PUT", "/pos/landed-prices", body, owner, 204)
	check("21000.0000", "252000.0000")
	body["version"] = "3"
	exec(`INSERT INTO app.warehouses(id,code,name) VALUES('00000000-0000-0000-0000-000000000013','HOME','Home')`)
	body["warehouse_id"] = "00000000-0000-0000-0000-000000000013"
	call("PUT", "/pos/landed-prices", body, owner, 409)
	check("21000.0000", "252000.0000")
	body["warehouse_id"] = warehouse
	body["retail_value"] = "NaN"
	call("PUT", "/pos/landed-prices", body, owner, 400)
	body["retail_value"] = "10"
	// Audit failure must roll back both unit prices and the product version.
	exec(`CREATE FUNCTION app.reject_landed_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='warehouse_prices.landed_save' THEN RAISE EXCEPTION 'test audit failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER reject_landed_audit BEFORE INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.reject_landed_audit()`)
	call("PUT", "/pos/landed-prices", body, owner, 503)
	check("21000.0000", "252000.0000")
	exec(`DROP TRIGGER reject_landed_audit ON app.audit_logs`)
	call("PUT", "/pos/landed-prices", body, owner, 204)
	check("22000.0000", "264000.0000")
	var count int
	if e = conn.QueryRow(ctx, `SELECT count(*) FROM app.audit_logs WHERE action='warehouse_prices.landed_save' AND new_value->'cost_reference'->>'landed_cost_mmk'='240000.0000'`).Scan(&count); e != nil || count != 3 {
		t.Fatal(count, e)
	}
}
