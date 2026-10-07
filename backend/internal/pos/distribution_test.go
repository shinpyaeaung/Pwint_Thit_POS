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
	"sync"
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

func TestDistributionIntegration(t *testing.T) {
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
	var unspecified bool
	if e = conn.QueryRow(ctx, `SELECT fulfillment IS NULL FROM app.shipments WHERE id='00000000-0000-0000-0000-000000000050'`).Scan(&unspecified); e != nil || !unspecified {
		t.Fatal("invented historical delivery details", e)
	}
	const product = "00000000-0000-0000-0000-000000000020"
	const warehouse = "00000000-0000-0000-0000-000000000012"
	exec(`INSERT INTO app.product_units(product_id,unit_code,units_per_pack,retail_price_mmk,wholesale_price_mmk) VALUES($1,'BOTTLE',1,40000,35000);`, product)
	exec(`UPDATE app.batches SET finalized_at=now(); UPDATE app.product_units SET retail_price_mmk=480000,wholesale_price_mmk=420000 WHERE unit_code='CARTON'`)
	price := map[string]any{"product_id": product, "warehouse_id": warehouse, "unit_code": "BOTTLE", "version": "1", "retail_price_mmk": "45000", "wholesale_price_mmk": "41000"}
	call("PUT", "/pos/prices", price, staff, 403)
	call("PUT", "/pos/prices", price, owner, 204)
	call("PUT", "/pos/prices", price, owner, 409)
	line := map[string]any{"product_id": product, "unit_code": "BOTTLE", "units_per_pack": "1", "quantity": "1", "unit_price_mmk": "45000", "discount_mmk": "0"}
	body := map[string]any{"request_id": "90000000-0000-0000-0000-000000000001", "warehouse_id": warehouse, "pricing_mode": "RETAIL", "tender_mmk": "45000", "payment_method": "CASH", "items": []any{line}, "fulfillment": map[string]string{"mode": "DELIVERY", "person_name": "Driver", "vehicle_number": "YGN-123"}}
	quote := call("POST", "/pos/quote", body, owner, 200)
	if quote["total_mmk"] != "45000.0000" {
		t.Fatal(quote)
	}
	line["unit_price_mmk"] = "40000"
	call("POST", "/pos/quote", body, owner, 409)
	line["unit_price_mmk"] = "45000"
	body["quote_hash"] = quote["quote_hash"]
	sale := call("POST", "/pos/checkout", body, owner, 201)
	invoice := call("GET", "/sales/"+sale["id"].(string), nil, owner, 200)
	if invoice["fulfillment"].(map[string]any)["vehicle_number"] != "YGN-123" {
		t.Fatal(invoice)
	}
	exec(`INSERT INTO app.warehouses(id,code,name) VALUES('00000000-0000-0000-0000-000000000013','HOME','Home warehouse')`)
	for w, want := range map[string]string{warehouse: "45000.0000", "00000000-0000-0000-0000-000000000013": "40000.0000"} {
		response := raw("GET", "/pos/products?warehouse_id="+w, nil, owner)
		var products []map[string]any
		if e = json.Unmarshal(response.Body.Bytes(), &products); e != nil {
			t.Fatal(e)
		}
		for _, p := range products {
			if p["id"] == product {
				for _, u := range p["packaging"].([]any) {
					pack := u.(map[string]any)
					if pack["unit_code"] == "BOTTLE" && pack["retail_price_mmk"] != want {
						t.Fatal(pack)
					}
				}
			}
		}
	}
	// Pack damage converts exactly, checks stock and retains retry semantics.
	var version string
	if e = conn.QueryRow(ctx, `SELECT version::text FROM app.inventory WHERE warehouse_id=$1 AND batch_id='00000000-0000-0000-0000-000000000070'`, warehouse).Scan(&version); e != nil {
		t.Fatal(e)
	}
	issue := map[string]any{"request_id": "90000000-0000-0000-0000-000000000002", "batch_id": "00000000-0000-0000-0000-000000000070", "warehouse_id": warehouse, "version": version, "kind": "DAMAGE", "bucket": "SELLABLE", "quantity": "1", "unit_code": "CARTON", "units_per_pack": "12", "reason": "Broken carton"}
	call("POST", "/stock-issues", issue, owner, 409)
	issue["quantity"] = "0.5"
	first := call("POST", "/stock-issues", issue, owner, 200)
	again := call("POST", "/stock-issues", issue, owner, 200)
	if first["id"] != again["id"] {
		t.Fatal("duplicate damage")
	}
	var qty string
	if e = conn.QueryRow(ctx, `SELECT quantity::text FROM app.damaged_products WHERE id=$1`, first["id"]).Scan(&qty); e != nil || qty != "6.000000" {
		t.Fatal(qty, e)
	}
	// Cargo payments serialize, are separate from supplier debt, and roll back on audit failure.
	exec(`INSERT INTO app.transportation_stages(id,shipment_id,stage_number,start_location,destination,provider_name,transportation_fee_mmk) VALUES('90000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000050',1,'A','B','Cargo terminal',100)`)
	payment := map[string]any{"request_id": "90000000-0000-0000-0000-000000000004", "target_id": "90000000-0000-0000-0000-000000000003", "kind": "TRANSPORT", "amount": "40", "method_code": "KBZPAY", "paid_at": "2026-10-06T12:00:00+06:30"}
	call("GET", "/transport-payments", nil, staff, 403)
	call("GET", "/customer-payments", nil, staff, 403)
	call("GET", "/customer-payments", nil, owner, 200)
	call("POST", "/transport-payments", payment, staff, 403)
	first = call("POST", "/transport-payments", payment, owner, 201)
	again = call("POST", "/transport-payments", payment, owner, 201)
	if first["id"] != again["id"] {
		t.Fatal("duplicate payment")
	}
	exec(`CREATE FUNCTION app.reject_transport_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='transport_payments.create' THEN RAISE EXCEPTION 'test audit failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER reject_transport_audit BEFORE INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.reject_transport_audit()`)
	payment["request_id"] = "90000000-0000-0000-0000-000000000005"
	payment["amount"] = "60"
	call("POST", "/transport-payments", payment, owner, 503)
	exec(`DROP TRIGGER reject_transport_audit ON app.audit_logs;DROP FUNCTION app.reject_transport_audit()`)
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for _, request := range []string{"90000000-0000-0000-0000-000000000005", "90000000-0000-0000-0000-000000000006"} {
		wg.Add(1)
		go func(request string) {
			defer wg.Done()
			p := map[string]any{}
			for k, v := range payment {
				p[k] = v
			}
			p["request_id"] = request
			codes <- raw("POST", "/transport-payments", p, owner).Code
		}(request)
	}
	wg.Wait()
	close(codes)
	ok, denied := 0, 0
	for c := range codes {
		if c == 201 {
			ok++
		}
		if c == 409 {
			denied++
		}
	}
	if ok != 1 || denied != 1 {
		t.Fatal(ok, denied)
	}
	var count int
	if e = conn.QueryRow(ctx, `SELECT count(*) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.transportation_stage_id=$1 AND (p.supplier_id IS NOT NULL OR p.customer_id IS NOT NULL)`, payment["target_id"]).Scan(&count); e != nil || count != 0 {
		t.Fatal("wrong payment party", e, count)
	}
	exec(`UPDATE app.shipments SET status='CANCELLED' WHERE id='00000000-0000-0000-0000-000000000050'`)
	paidCharges := call("GET", "/transport-payments?status=PAID", nil, owner, 200)
	if len(paidCharges["records"].([]any)) != 1 || paidCharges["records"].([]any)[0].(map[string]any)["shipment_status"] != "CANCELLED" {
		t.Fatal("cancelled shipment erased payment history", paidCharges)
	}
	exec(`UPDATE app.shipments SET status='PREPARING' WHERE id='00000000-0000-0000-0000-000000000050'`)
	exec(`INSERT INTO app.shipment_expenses(id,shipment_id,category,description,currency_code,amount_original,mmk_per_unit,incurred_at,recorded_by) VALUES('90000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000050','Handling','Terminal loading','INR',100,25,now(),'00000000-0000-0000-0000-000000000001')`)
	payment["request_id"] = "90000000-0000-0000-0000-000000000008"
	payment["target_id"] = "90000000-0000-0000-0000-000000000007"
	payment["kind"] = "ADDITIONAL_COST"
	payment["amount"] = "100"
	costPayment := call("POST", "/transport-payments", payment, owner, 201)
	var mmk string
	if e = conn.QueryRow(ctx, `SELECT amount_mmk::text FROM app.payments WHERE id=$1`, costPayment["id"]).Scan(&mmk); e != nil || mmk != "2500.0000" {
		t.Fatal(mmk, e)
	}
	if _, e = conn.Exec(ctx, `UPDATE app.payments SET notes='rewrite' WHERE id=$1`, costPayment["id"]); e == nil {
		t.Fatal("payment history changed")
	}

}
