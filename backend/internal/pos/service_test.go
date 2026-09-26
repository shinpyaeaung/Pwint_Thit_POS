package pos_test

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/pos"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
)

func TestPOSIntegration(t *testing.T) {
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
		_, err = conn.Exec(ctx, `WITH u AS (INSERT INTO app.users(id,username,display_name,password_hash,role_code) VALUES(('00000000-0000-0000-0000-'||lpad(($4::int+1)::text,12,'0'))::uuid,$1,$1,'test-only-placeholder-hash',$2) RETURNING id) INSERT INTO app.user_sessions(user_id,token_hash,expires_at) SELECT id,$3,now()+interval '1 hour' FROM u`, name, role, h[:], i)
		if err != nil {
			t.Fatal(err)
		}
	}
	q := database.New(pool)
	a := authz.New(q)
	r := httpapi.New(q, slog.New(slog.NewJSONHandler(io.Discard, nil)), a, authn.New(pool, authn.Options{AllowedOrigins: []string{"http://app.test"}}))
	pos.New(pool).Register(r, a)
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
	fixture, e := os.ReadFile("../../../database/tests/fixture.sql")
	if e != nil {
		t.Fatal(e)
	}
	_, err = conn.Exec(ctx, string(fixture[strings.Index(string(fixture), "INSERT INTO app.suppliers"):]))
	if err != nil {
		t.Fatal(err)
	}
	_, err = conn.Exec(ctx, `INSERT INTO app.product_units(product_id,unit_code,units_per_pack,retail_price_mmk,wholesale_price_mmk) VALUES('00000000-0000-0000-0000-000000000020','BOTTLE',1,40000,35000);UPDATE app.product_units SET retail_price_mmk=480000,wholesale_price_mmk=420000 WHERE unit_code='CARTON';UPDATE app.batches SET received_at=now()-interval '10 days',finalized_at=now();
 INSERT INTO app.goods_receiving_items(id,goods_receiving_id,shipment_id,shipment_item_id,product_id,expected_quantity,received_quantity,damaged_quantity,batch_number) SELECT '00000000-0000-0000-0000-000000000062',goods_receiving_id,shipment_id,shipment_item_id,product_id,20,20,0,'BATCH-2' FROM app.goods_receiving_items LIMIT 1;
 INSERT INTO app.batches(id,product_id,receiving_item_id,batch_number,received_at,purchase_cost_mmk,sellable_quantity,finalized_at) VALUES('00000000-0000-0000-0000-000000000071','00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000062','BATCH-2',now(),400000,20,now());
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,receiving_item_id,idempotency_key,occurred_at,recorded_by) VALUES('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000071','RECEIPT',20,20000,'00000000-0000-0000-0000-000000000062','second-batch',now(),'00000000-0000-0000-0000-000000000001');`)
	if err != nil {
		t.Fatal(err)
	}

	_, err = conn.Exec(ctx, `INSERT INTO app.goods_receiving_items(id,goods_receiving_id,shipment_id,shipment_item_id,product_id,expected_quantity,received_quantity,damaged_quantity,batch_number) SELECT '00000000-0000-0000-0000-000000000063',goods_receiving_id,shipment_id,shipment_item_id,product_id,40,40,0,'EXPIRED' FROM app.goods_receiving_items LIMIT 1;
 INSERT INTO app.batches(id,product_id,receiving_item_id,batch_number,received_at,expires_on,purchase_cost_mmk,sellable_quantity,finalized_at) VALUES('00000000-0000-0000-0000-000000000072','00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000063','EXPIRED',now()-interval '20 days',app.business_date()-1,9000,40,now());
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,receiving_item_id,idempotency_key,occurred_at,recorded_by) VALUES('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000072','RECEIPT',40,225,'00000000-0000-0000-0000-000000000063','expired-batch',now(),'00000000-0000-0000-0000-000000000001');`)
	if err != nil {
		t.Fatal(err)
	}
	line := map[string]any{"product_id": "00000000-0000-0000-0000-000000000020", "unit_code": "BOTTLE", "units_per_pack": "1", "quantity": "10", "unit_price_mmk": "40000", "discount_mmk": "0"}
	body := map[string]any{"request_id": "60000000-0000-0000-0000-000000000001", "warehouse_id": "00000000-0000-0000-0000-000000000012", "customer_id": "", "pricing_mode": "RETAIL", "payment_method": "CASH", "payment_reference": "", "tender_mmk": "450000", "reason": "", "due_date": "", "quote_hash": "", "items": []map[string]any{line}}
	call("POST", "/pos/quote", body, "", 401)
	call("POST", "/pos/checkout", body, staff, 403)
	quote := call("POST", "/pos/quote", body, owner, 200)
	if quote["cost_mmk"] != "280000.0000" || quote["change_mmk"] != "50000.0000" {
		t.Fatal("FIFO or change", quote)
	}
	allocations := quote["lines"].([]any)[0].(map[string]any)["allocations"].([]any)
	if len(allocations) != 2 || allocations[0].(map[string]any)["quantity"] != "8.000000" {
		t.Fatal("FIFO allocations", allocations)
	}
	var qty string
	err = conn.QueryRow(ctx, `SELECT available_quantity::text FROM app.inventory WHERE batch_id='00000000-0000-0000-0000-000000000070'`).Scan(&qty)
	if err != nil || qty != "8.000000" {
		t.Fatal("quote mutated inventory", qty, err)
	}
	body["quote_hash"] = quote["quote_hash"]
	// Inject failures into the real database, including deferred failure at COMMIT.
	// Compare complete ledger rows and inventory, not just invoice counts.
	snapshot := func() string {
		t.Helper()
		var value string
		err := conn.QueryRow(ctx, `SELECT jsonb_build_object(
   'sales',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.sales s),
   'items',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.sale_items s),
   'costs',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.sale_item_batches s),
   'inventory',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY warehouse_id,batch_id),'[]') FROM app.inventory s),
   'movements',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.inventory_movements s),
   'payments',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.payments s),
   'allocations',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.payment_allocations s),
   'audit',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.audit_logs s)
  )::text`).Scan(&value)
		if err != nil {
			t.Fatal(err)
		}
		return value
	}
	if _, err := conn.Exec(ctx, `CREATE FUNCTION app.test_checkout_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected checkout failure'; END $$`); err != nil {
		t.Fatal(err)
	}
	for _, stage := range []struct {
		table, event string
		deferred     bool
	}{
		{"sales", "INSERT", false}, {"sale_items", "INSERT", false}, {"sale_item_batches", "INSERT", false},
		{"inventory_movements", "INSERT", false}, {"inventory", "UPDATE", false}, {"payments", "INSERT", false},
		{"payment_allocations", "INSERT", false}, {"payments", "UPDATE", false}, {"sales", "UPDATE", false},
		{"audit_logs", "INSERT", false}, {"audit_logs", "INSERT", true},
	} {
		t.Run("rollback_"+stage.table+"_"+stage.event+fmt.Sprint(stage.deferred), func(t *testing.T) {
			before := snapshot()
			definition := "CREATE TRIGGER test_checkout_failure AFTER " + stage.event + " ON app." + stage.table + " FOR EACH ROW EXECUTE FUNCTION app.test_checkout_failure()"
			if stage.deferred {
				definition = "CREATE CONSTRAINT TRIGGER test_checkout_failure AFTER INSERT ON app.audit_logs DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app.test_checkout_failure()"
			}
			if _, err := conn.Exec(ctx, definition); err != nil {
				t.Fatal(err)
			}
			defer func() {
				if _, err := conn.Exec(ctx, "DROP TRIGGER test_checkout_failure ON app."+stage.table); err != nil {
					t.Fatal(err)
				}
			}()
			failed := raw("POST", "/pos/checkout", body, owner)
			if failed.Code != 503 {
				t.Fatalf("failure returned %d: %s", failed.Code, failed.Body.String())
			}
			if after := snapshot(); after != before {
				t.Fatal("failed checkout left partial records or changed stock")
			}
		})
	}
	// The exact failed request can now succeed; retries still create just one sale.
	var wg sync.WaitGroup
	results := make(chan int, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); results <- raw("POST", "/pos/checkout", body, owner).Code }()
	}
	wg.Wait()
	close(results)
	for v := range results {
		if v != 201 {
			t.Fatal("checkout retry", v)
		}
	}
	sale := call("POST", "/pos/checkout", body, owner, 201)
	invoice := call("GET", "/sales/"+sale["id"].(string), nil, owner, 200)
	if invoice["paid_mmk"] != "400000.0000" || invoice["profit_mmk"] != "120000.0000" {
		t.Fatal("invoice ledger", invoice)
	}
	var count int
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.inventory_movements WHERE movement_type='SALE'`).Scan(&count); err != nil || count != 2 {
		t.Fatal("duplicate movements", err, count)
	}
	body["request_id"] = "60000000-0000-0000-0000-000000000002"
	line["quantity"] = "19"
	body["tender_mmk"] = "800000"
	call("POST", "/pos/quote", body, owner, 409)
	line["quantity"] = "1"
	line["unit_price_mmk"] = "1"
	call("POST", "/pos/quote", body, owner, 409)
	line["unit_price_mmk"] = "40000"
	body["tender_mmk"] = "10000"
	call("POST", "/pos/quote", body, owner, 409)
	body["customer_id"] = "00000000-0000-0000-0000-000000000011"
	body["due_date"] = "2099-01-01"
	call("POST", "/pos/quote", body, owner, 409)
	_, err = conn.Exec(ctx, `UPDATE app.customers SET credit_limit_mmk=100000;INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT '00000000-0000-0000-0000-000000000002',code,'00000000-0000-0000-0000-000000000001' FROM app.permissions WHERE code IN ('sales.create','payments.manage')`)
	if err != nil {
		t.Fatal(err)
	}
	line["discount_mmk"] = "1"
	body["reason"] = "Discount"
	call("POST", "/pos/quote", body, staff, 409)
	line["discount_mmk"] = "0"
	quote = call("POST", "/pos/quote", body, staff, 200)
	if _, ok := quote["cost_mmk"]; ok {
		t.Fatal("cost leaked")
	}
	if _, ok := quote["profit_mmk"]; ok {
		t.Fatal("profit leaked")
	}
	body["quote_hash"] = quote["quote_hash"]
	credit := call("POST", "/pos/checkout", body, staff, 201)
	var debt string
	if err = conn.QueryRow(ctx, `SELECT outstanding_mmk::text FROM app.customer_debts WHERE sale_id=$1`, credit["id"]).Scan(&debt); err != nil || debt != "30000.0000" {
		t.Fatal("credit ledger", debt, err)
	}
	call("GET", "/sales/"+sale["id"].(string), nil, staff, 404)
	own := call("GET", "/sales/"+credit["id"].(string), nil, staff, 200)
	if _, ok := own["cost_mmk"]; ok {
		t.Fatal("invoice cost leaked")
	}
	// Below-cost protection applies even without a discount (e.g. a configured low retail price).
	_, err = conn.Exec(ctx, `UPDATE app.product_units SET retail_price_mmk=1000 WHERE unit_code='BOTTLE'`)
	if err != nil {
		t.Fatal(err)
	}
	line["unit_price_mmk"] = "1000"
	body["tender_mmk"] = "1000"
	body["customer_id"] = ""
	body["due_date"] = ""
	body["reason"] = "Owner-approved clearance"
	call("POST", "/pos/quote", body, staff, 409)
	low := call("POST", "/pos/quote", body, owner, 200)
	if low["lines"].([]any)[0].(map[string]any)["below_cost"] != true {
		t.Fatal("missing loss warning")
	}
	_, err = conn.Exec(ctx, `UPDATE app.product_units SET retail_price_mmk=40000 WHERE unit_code='BOTTLE'`)
	if err != nil {
		t.Fatal(err)
	}
	line["unit_price_mmk"] = "40000"
	line["quantity"] = "17"
	body["tender_mmk"] = "700000"
	body["reason"] = ""
	quote = call("POST", "/pos/quote", body, owner, 200)
	body["quote_hash"] = quote["quote_hash"]
	results = make(chan int, 2)
	for _, request := range []string{"60000000-0000-0000-0000-000000000003", "60000000-0000-0000-0000-000000000004"} {
		payload := map[string]any{}
		for k, v := range body {
			payload[k] = v
		}
		payload["request_id"] = request
		wg.Add(1)
		go func() { defer wg.Done(); results <- raw("POST", "/pos/checkout", payload, owner).Code }()
	}
	wg.Wait()
	close(results)
	success, conflict := 0, 0
	for code := range results {
		if code == 201 {
			success++
		} else if code == 409 {
			conflict++
		} else {
			t.Fatal("concurrent checkout", code)
		}
	}
	if success != 1 || conflict != 1 {
		t.Fatal("overselling not prevented", success, conflict)
	}
	if err = conn.QueryRow(ctx, `SELECT available_quantity::text FROM app.inventory WHERE batch_id='00000000-0000-0000-0000-000000000072'`).Scan(&qty); err != nil || qty != "40.000000" {
		t.Fatal("expired goods sold", qty, err)
	}

	for _, q := range []string{`UPDATE app.sale_item_batches SET unit_cost_mmk=0 WHERE sale_item_id IN(SELECT id FROM app.sale_items WHERE sale_id IN(SELECT id FROM app.sales WHERE status='POSTED'))`, `UPDATE app.sales SET invoice_document='{}' WHERE status='POSTED'`, `UPDATE app.inventory SET sellable_quantity=100`} {
		if _, err = conn.Exec(ctx, q); err == nil {
			t.Fatal("immutable financial history changed", q)
		}
	}
}
