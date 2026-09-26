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

	// Customer-specific prices use the selected pack and preserve below-cost rules.
	customerInput := map[string]any{"code": "SPECIAL", "name": "Wholesale customer", "business_name": "Shop", "phone": "099", "address": "Yangon", "customer_type": "WHOLESALE", "credit_limit_mmk": "1000000", "notes": "Account", "is_active": true}
	call("POST", "/customers", customerInput, staff, 403)
	specialCustomer := call("POST", "/customers", customerInput, owner, 200)["id"].(string)
	specialPath := "/customers/" + specialCustomer
	call("PUT", specialPath+"/prices", map[string]any{"version": "1", "product_id": line["product_id"], "unit_code": "BOTTLE", "price_mmk": "50000", "remove": false}, owner, 204)
	body["customer_id"] = specialCustomer
	body["due_date"] = "2099-01-01"
	body["tender_mmk"] = "300000"
	line["unit_price_mmk"] = "50000"
	specialQuote := call("POST", "/pos/quote", body, owner, 200)
	if specialQuote["total_mmk"] != "500000.0000" || specialQuote["outstanding_mmk"] != "200000.0000" {
		t.Fatal("special pricing", specialQuote)
	}
	line["unit_price_mmk"] = "40000"
	call("POST", "/pos/quote", body, owner, 409)
	call("PUT", specialPath+"/prices", map[string]any{"version": "2", "product_id": line["product_id"], "unit_code": "BOTTLE", "price_mmk": "0", "remove": true}, owner, 204)
	body["customer_id"] = ""
	body["due_date"] = ""
	body["tender_mmk"] = "450000"
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
   'returns',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.sales_returns s),
   'return_items',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.sales_return_items s),
   'purchase_returns',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.purchase_returns s),
   'purchase_return_items',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.purchase_return_items s),
   'damage',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.damaged_products s),
   'missing',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.missing_products s),
   'operations',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY request_id),'[]') FROM app.stock_operations s),
   'approvals',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY id),'[]') FROM app.approvals s),
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
	body["request_id"] = "60000000-0000-0000-0000-000000000005"
	restricted := call("POST", "/pos/quote", body, staff, 200)
	if restricted["requires_below_cost_approval"] != true || restricted["can_approve_below_cost"] != false {
		t.Fatal("missing restricted warning", restricted)
	}
	if _, ok := restricted["cost_mmk"]; ok {
		t.Fatal("restricted quote leaked cost")
	}
	body["quote_hash"] = restricted["quote_hash"]
	body["approve_below_cost"] = true // Forged UI approval cannot bypass the backend.
	beforeRestricted := snapshot()
	call("POST", "/pos/checkout", body, staff, 409)
	if snapshot() != beforeRestricted {
		t.Fatal("unauthorized sale mutated ledger")
	}
	low := call("POST", "/pos/quote", body, owner, 200)
	if low["lines"].([]any)[0].(map[string]any)["below_cost"] != true {
		t.Fatal("missing loss warning")
	}
	body["quote_hash"] = low["quote_hash"]
	body["approve_below_cost"] = false
	call("POST", "/pos/checkout", body, owner, 409)
	body["approve_below_cost"] = true
	body["reason"] = " "
	call("POST", "/pos/checkout", body, owner, 409)
	body["reason"] = "Owner-approved clearance"
	body["quote_hash"] = "stale"
	call("POST", "/pos/checkout", body, owner, 409)
	body["quote_hash"] = low["quote_hash"]
	// Approval/audit failures roll back the sale, payment, costs and movement too.
	for _, table := range []string{"approvals", "audit_logs"} {
		before := snapshot()
		if _, err := conn.Exec(ctx, "CREATE TRIGGER test_checkout_failure AFTER INSERT ON app."+table+" FOR EACH ROW EXECUTE FUNCTION app.test_checkout_failure()"); err != nil {
			t.Fatal(err)
		}
		call("POST", "/pos/checkout", body, owner, 503)
		if snapshot() != before {
			t.Fatal("approval failure left a partial sale")
		}
		if _, err := conn.Exec(ctx, "DROP TRIGGER test_checkout_failure ON app."+table); err != nil {
			t.Fatal(err)
		}
	}
	approved := call("POST", "/pos/checkout", body, owner, 201)
	call("POST", "/pos/checkout", body, owner, 201)
	var correct bool
	err = conn.QueryRow(ctx, `SELECT count(*)=1 AND bool_and(a.decided_by=s.created_by AND a.consumed_at IS NOT NULL AND a.request_payload=s.invoice_document AND a.request_hash=sha256(convert_to(a.request_payload::text,'UTF8'))) FROM app.approvals a JOIN app.sales s ON s.id=a.sale_id WHERE a.sale_id=$1`, approved["id"]).Scan(&correct)
	if err != nil || !correct {
		t.Fatal("missing or duplicate bound approval", err)
	}
	err = conn.QueryRow(ctx, `SELECT count(*)=1 FROM app.audit_logs WHERE entity_id=$1 AND action='sales.below_cost.approved' AND reason='Owner-approved clearance' AND actor_id='00000000-0000-0000-0000-000000000001'`, approved["id"]).Scan(&correct)
	if err != nil || !correct {
		t.Fatal("approval audit missing", err)
	}
	for _, sql := range []string{`UPDATE app.approvals SET reason='changed' WHERE consumed_at IS NOT NULL`, `DELETE FROM app.approvals WHERE consumed_at IS NOT NULL`} {
		if _, err := conn.Exec(ctx, sql); err == nil {
			t.Fatal("consumed approval mutable")
		}
	}
	grant := `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002','sales.sell_below_cost','00000000-0000-0000-0000-000000000001')`
	if _, err := conn.Exec(ctx, grant); err != nil {
		t.Fatal(err)
	}
	body["request_id"] = "60000000-0000-0000-0000-000000000006"
	low = call("POST", "/pos/quote", body, staff, 200)
	if low["can_approve_below_cost"] != true {
		t.Fatal("staff grant not recognized")
	}
	body["quote_hash"] = low["quote_hash"]
	if _, err := conn.Exec(ctx, `DELETE FROM app.user_permissions WHERE permission_code='sales.sell_below_cost'`); err != nil {
		t.Fatal(err)
	}
	call("POST", "/pos/checkout", body, staff, 409) // Permission is rechecked after preview.
	if _, err := conn.Exec(ctx, grant); err != nil {
		t.Fatal(err)
	}
	delegated := call("POST", "/pos/checkout", body, staff, 201)
	err = conn.QueryRow(ctx, `SELECT count(*)=1 FROM app.approvals WHERE sale_id=$1 AND decided_by='00000000-0000-0000-0000-000000000002'`, delegated["id"]).Scan(&correct)
	if err != nil || !correct {
		t.Fatal("delegated approval missing", err)
	}
	// Equality is not a loss. One decimal step below the actual cost is a loss.
	if _, err := conn.Exec(ctx, `UPDATE app.product_units SET retail_price_mmk=20000 WHERE unit_code='BOTTLE'`); err != nil {
		t.Fatal(err)
	}
	line["unit_price_mmk"] = "20000"
	body["tender_mmk"] = "20000"
	equal := call("POST", "/pos/quote", body, owner, 200)
	if equal["requires_below_cost_approval"] != false {
		t.Fatal("equal cost requires approval")
	}
	line["discount_mmk"] = "0.0001"
	loss := call("POST", "/pos/quote", body, owner, 200)
	if loss["requires_below_cost_approval"] != true {
		t.Fatal("exact decimal loss missed")
	}
	line["discount_mmk"] = "0"
	body["approve_below_cost"] = false
	_, err = conn.Exec(ctx, `UPDATE app.product_units SET retail_price_mmk=40000 WHERE unit_code='BOTTLE'`)
	if err != nil {
		t.Fatal(err)
	}
	line["unit_price_mmk"] = "40000"
	line["quantity"] = "15"
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

	// Seed a posted historical invoice; collections use the same live debt ledger as POS.
	var historySale string
	err = conn.QueryRow(ctx, `WITH s AS(INSERT INTO app.sales(invoice_number,customer_id,warehouse_id,pricing_mode,sold_at,due_date,created_by) VALUES('CREDIT-500K',$1,'00000000-0000-0000-0000-000000000012','WHOLESALE',now(),'2099-01-01','00000000-0000-0000-0000-000000000001') RETURNING id), i AS(INSERT INTO app.sale_items(sale_id,line_number,product_id,unit_code,units_per_pack,quantity,unit_price_mmk) SELECT id,1,'00000000-0000-0000-0000-000000000020','BOTTLE',1,1,500000 FROM s) SELECT id::text FROM s`, specialCustomer).Scan(&historySale)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = conn.Exec(ctx, `UPDATE app.sales SET status='POSTED',posted_at=now() WHERE id=$1`, historySale); err != nil {
		t.Fatal(err)
	}
	unpaid := call("GET", specialPath+"/history", nil, owner, 200)["invoices"].([]any)[0].(map[string]any)
	if unpaid["payment_status"] != "UNPAID" {
		t.Fatal("unpaid status", unpaid)
	}
	collection := map[string]any{"request_id": "70000000-0000-0000-0000-000000000001", "sale_id": historySale, "amount_mmk": "300000", "method": "CASH", "reference": "Receipt 1"}
	call("POST", specialPath+"/payments", collection, staff, 403)
	beforePayment := snapshot()
	if _, err = conn.Exec(ctx, `CREATE TRIGGER test_checkout_failure AFTER INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.test_checkout_failure()`); err != nil {
		t.Fatal(err)
	}
	call("POST", specialPath+"/payments", collection, owner, 503)
	if snapshot() != beforePayment {
		t.Fatal("collection audit failure left payment")
	}
	if _, err = conn.Exec(ctx, `DROP TRIGGER test_checkout_failure ON app.audit_logs`); err != nil {
		t.Fatal(err)
	}
	call("POST", specialPath+"/payments", collection, owner, 201)
	call("POST", specialPath+"/payments", collection, owner, 201)
	history := call("GET", specialPath+"/history", nil, owner, 200)["invoices"].([]any)[0].(map[string]any)
	if history["total_mmk"] != "500000.0000" || history["amount_paid_mmk"] != "300000.0000" || history["outstanding_mmk"] != "200000.0000" || history["payment_status"] != "PARTIALLY_PAID" {
		t.Fatal("collection balance", history)
	}
	collection["amount_mmk"] = "200000" // UUID cannot be reused with edited details.
	call("POST", specialPath+"/payments", collection, owner, 409)
	results = make(chan int, 2)
	for _, request := range []string{"70000000-0000-0000-0000-000000000002", "70000000-0000-0000-0000-000000000003"} {
		payload := map[string]any{}
		for k, v := range collection {
			payload[k] = v
		}
		payload["request_id"] = request
		wg.Add(1)
		go func() { defer wg.Done(); results <- raw("POST", specialPath+"/payments", payload, owner).Code }()
	}
	wg.Wait()
	close(results)
	success, conflict = 0, 0
	for code := range results {
		if code == 201 {
			success++
		} else if code == 409 {
			conflict++
		} else {
			t.Fatal(code)
		}
	}
	if success != 1 || conflict != 1 {
		t.Fatal("concurrent collection overpaid", success, conflict)
	}
	history = call("GET", specialPath+"/history", nil, owner, 200)["invoices"].([]any)[0].(map[string]any)
	if history["outstanding_mmk"] != "0.0000" || history["payment_status"] != "PAID" {
		t.Fatal("paid ledger", history)
	}
	detail := call("GET", specialPath, nil, owner, 200)
	if detail["outstanding_mmk"] != "0.0000" {
		t.Fatal("customer balance", detail)
	}
	customerInput["version"] = detail["version"]
	customerInput["is_active"] = false
	call("PUT", specialPath, customerInput, owner, 200)
	call("PUT", specialPath, customerInput, owner, 409)

	// Phase 17: returns restore original batch costs; previews and failures are pure.
	source := call("GET", "/returns/sales/"+sale["id"].(string), nil, owner, 200)
	returnLines := source["items"].([]any)
	originalBatch := returnLines[0].(map[string]any)["sale_item_batch_id"]
	returnLine := map[string]any{"sale_item_batch_id": originalBatch, "quantity": "2", "disposition": "SELLABLE"}
	returnBody := map[string]any{"request_id": "80000000-0000-0000-0000-000000000001", "sale_id": sale["id"], "resolution": "REFUND", "reason": "Returned unopened bottles", "method": "CASH", "reference": "Refund receipt", "approve_refund": true, "items": []map[string]any{returnLine}}
	call("POST", "/returns/sales/preview", returnBody, staff, 403)
	beforeReturn := snapshot()
	previewReturn := call("POST", "/returns/sales/preview", returnBody, owner, 200)
	if previewReturn["credit_mmk"] != "80000.0000" || previewReturn["refund_mmk"] != "80000.0000" {
		t.Fatal("return preview", previewReturn)
	}
	if snapshot() != beforeReturn {
		t.Fatal("return preview changed ledger")
	}
	returnBody["quote_hash"] = previewReturn["quote_hash"]
	for _, table := range []string{"sales_returns", "sales_return_items", "inventory_movements", "payments", "payment_allocations", "approvals", "audit_logs", "stock_operations"} {
		before := snapshot()
		if _, err = conn.Exec(ctx, "CREATE TRIGGER test_checkout_failure AFTER INSERT ON app."+table+" FOR EACH ROW EXECUTE FUNCTION app.test_checkout_failure()"); err != nil {
			t.Fatal(err)
		}
		call("POST", "/returns/sales", returnBody, owner, 503)
		if snapshot() != before {
			t.Fatal("return failure left partial ledger", table)
		}
		if _, err = conn.Exec(ctx, "DROP TRIGGER test_checkout_failure ON app."+table); err != nil {
			t.Fatal(err)
		}
	}
	returnedSale := call("POST", "/returns/sales", returnBody, owner, 200)
	call("POST", "/returns/sales", returnBody, owner, 200)
	if err = conn.QueryRow(ctx, `SELECT count(*)=1 AND bool_and(unit_cost_mmk=30000) FROM app.sales_return_items WHERE sales_return_id=$1`, returnedSale["id"]).Scan(&correct); err != nil || !correct {
		t.Fatal("original return cost/deduplication", err)
	}
	returnBody["request_id"] = "80000000-0000-0000-0000-000000000002"
	returnLine["quantity"] = "9"
	call("POST", "/returns/sales/preview", returnBody, owner, 409)
	// A shortage cannot consume reserved stock. Damage transfers stock between buckets.
	var stockVersion string
	version := func() {
		t.Helper()
		if err = conn.QueryRow(ctx, `SELECT version::text FROM app.inventory WHERE batch_id='00000000-0000-0000-0000-000000000070'`).Scan(&stockVersion); err != nil {
			t.Fatal(err)
		}
	}
	version()
	issue := map[string]any{"request_id": "81000000-0000-0000-0000-000000000001", "batch_id": "00000000-0000-0000-0000-000000000070", "warehouse_id": "00000000-0000-0000-0000-000000000012", "version": stockVersion, "kind": "DAMAGE", "bucket": "SELLABLE", "quantity": "1", "reason": "Outer packaging torn", "notes": "Contents checked"}
	call("POST", "/stock-issues", issue, staff, 403)
	call("POST", "/stock-issues", issue, owner, 200)
	call("POST", "/stock-issues", issue, owner, 200)
	issue["request_id"] = "81000000-0000-0000-0000-000000000002"
	issue["kind"] = "MISSING"
	call("POST", "/stock-issues", issue, owner, 409) // Stale stock version.
	version()
	issue["version"] = stockVersion
	issue["quantity"] = "2"
	call("POST", "/stock-issues", issue, owner, 409)
	issue["quantity"] = "0.5"
	call("POST", "/stock-issues", issue, owner, 200)
	// Selling damaged stock never transfers it into normal sellable inventory.
	damageLine := map[string]any{"product_id": line["product_id"], "unit_code": "BOTTLE", "units_per_pack": "1", "quantity": "1", "unit_price_mmk": "1000", "discount_mmk": "0", "stock_bucket": "DAMAGED", "batch_id": issue["batch_id"]}
	damageSale := map[string]any{"request_id": "82000000-0000-0000-0000-000000000001", "warehouse_id": issue["warehouse_id"], "customer_id": "", "pricing_mode": "RETAIL", "payment_method": "CASH", "tender_mmk": "1000", "reason": "Usable damaged packaging clearance", "items": []map[string]any{damageLine}, "approve_below_cost": true}
	call("POST", "/pos/quote", damageSale, staff, 403)
	dq := call("POST", "/pos/quote", damageSale, owner, 200)
	damageSale["quote_hash"] = dq["quote_hash"]
	if dq["cost_mmk"] != "30000.0000" || dq["requires_below_cost_approval"] != true {
		t.Fatal("damaged actual cost", dq)
	}
	damagedInvoice := call("POST", "/pos/checkout", damageSale, owner, 201)
	if err = conn.QueryRow(ctx, `SELECT available_quantity::text FROM app.inventory WHERE batch_id='00000000-0000-0000-0000-000000000070'`).Scan(&qty); err != nil || qty != "0.500000" {
		t.Fatal("damaged sale used normal stock", qty, err)
	}
	if err = conn.QueryRow(ctx, `SELECT count(*)=1 AND bool_and(original_price_mmk=40000 AND reduced_price_mmk=1000 AND actual_unit_cost_mmk=30000 AND discount_loss_mmk=39000) FROM app.damaged_products WHERE sale_id=$1`, damagedInvoice["id"]).Scan(&correct); err != nil || !correct {
		t.Fatal("damaged price history", err)
	}
	// Returning a credit sale first cancels debt, then refunds only money actually received.
	creditSource := call("GET", "/returns/sales/"+credit["id"].(string), nil, owner, 200)["items"].([]any)[0].(map[string]any)
	creditReturn := map[string]any{"request_id": "83000000-0000-0000-0000-000000000001", "sale_id": credit["id"], "resolution": "REFUND", "reason": "Customer full return", "method": "CASH", "approve_refund": true, "items": []map[string]any{{"sale_item_batch_id": creditSource["sale_item_batch_id"], "quantity": "1", "disposition": "DAMAGED"}}}
	cr := call("POST", "/returns/sales/preview", creditReturn, owner, 200)
	if cr["credit_mmk"] != "40000.0000" || cr["refund_mmk"] != "10000.0000" {
		t.Fatal("refund exceeded paid amount", cr)
	}
	creditReturn["quote_hash"] = cr["quote_hash"]
	call("POST", "/returns/sales", creditReturn, owner, 200)
	if err = conn.QueryRow(ctx, `SELECT outstanding_mmk::text FROM app.customer_debts WHERE sale_id=$1`, credit["id"]).Scan(&debt); err != nil || debt != "0.0000" {
		t.Fatal("returned credit invoice balance", debt, err)
	}
	// Exchange links a separately paid replacement invoice and audits its refund.
	exchangeSource := call("GET", "/returns/sales/"+approved["id"].(string), nil, owner, 200)["items"].([]any)[0].(map[string]any)
	exchange := map[string]any{"request_id": "84000000-0000-0000-0000-000000000001", "sale_id": approved["id"], "replacement_sale_id": damagedInvoice["id"], "resolution": "EXCHANGE", "reason": "Replacement supplied", "method": "CASH", "approve_refund": true, "items": []map[string]any{{"sale_item_batch_id": exchangeSource["sale_item_batch_id"], "quantity": "1", "disposition": "SELLABLE"}}}
	eq := call("POST", "/returns/sales/preview", exchange, owner, 200)
	exchange["quote_hash"] = eq["quote_hash"]
	call("POST", "/returns/sales", exchange, owner, 200)
	// Original INR rate is preserved for a supplier refund; inventory leaves at landed cost.
	if _, err = conn.Exec(ctx, `UPDATE app.purchases SET status='POSTED',posted_at=now() WHERE id='00000000-0000-0000-0000-000000000040';
 INSERT INTO app.payments(id,payment_number,direction,method,currency_code,amount_original,mmk_per_unit,supplier_id,paid_at,recorded_by) VALUES('85000000-0000-0000-0000-000000000001','SUPPLIER-PAID','OUT','CASH','INR',10000,25,'00000000-0000-0000-0000-000000000010',now(),'00000000-0000-0000-0000-000000000001');
 INSERT INTO app.payment_allocations(payment_id,purchase_id,settlement_mmk,applied_mmk,applied_original) VALUES('85000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000040',250000,250000,10000);
 UPDATE app.payments SET status='POSTED',posted_at=now() WHERE id='85000000-0000-0000-0000-000000000001'`); err != nil {
		t.Fatal(err)
	}
	supplierReturn := map[string]any{"request_id": "85000000-0000-0000-0000-000000000002", "purchase_id": "00000000-0000-0000-0000-000000000040", "warehouse_id": issue["warehouse_id"], "resolution": "REFUND", "reason": "Supplier accepted damaged bottle", "method": "CASH", "approve_refund": true, "items": []map[string]any{{"batch_id": issue["batch_id"], "quantity": "1", "bucket": "DAMAGED"}}}
	sp := call("POST", "/returns/purchases/preview", supplierReturn, owner, 200)
	if sp["credit_original"] != "833.3333" || sp["refund_original"] != "833.3333" || sp["currency_code"] != "INR" {
		t.Fatal("supplier historical credit", sp)
	}
	supplierReturn["quote_hash"] = sp["quote_hash"]
	sr := call("POST", "/returns/purchases", supplierReturn, owner, 200)
	call("POST", "/returns/purchases", supplierReturn, owner, 200)
	if err = conn.QueryRow(ctx, `SELECT count(*)=1 AND bool_and(credit_mmk=20833.3325 AND inventory_cost_mmk=30000) FROM app.purchase_return_items WHERE purchase_return_id=$1`, sr["id"]).Scan(&correct); err != nil || !correct {
		t.Fatal("purchase cost/rate snapshot", err)
	}
	// Two return terminals cannot refund the same remaining six original bottles.
	returnLine["quantity"] = "6"
	returnBody["request_id"] = "86000000-0000-0000-0000-000000000001"
	rq := call("POST", "/returns/sales/preview", returnBody, owner, 200)
	returnBody["quote_hash"] = rq["quote_hash"]
	results = make(chan int, 2)
	for _, request := range []string{"86000000-0000-0000-0000-000000000001", "86000000-0000-0000-0000-000000000002"} {
		payload := map[string]any{}
		for k, v := range returnBody {
			payload[k] = v
		}
		payload["request_id"] = request
		wg.Add(1)
		go func() { defer wg.Done(); results <- raw("POST", "/returns/sales", payload, owner).Code }()
	}
	wg.Wait()
	close(results)
	success, conflict = 0, 0
	for code := range results {
		if code == 200 {
			success++
		} else if code == 409 {
			conflict++
		} else {
			t.Fatal("return concurrency", code)
		}
	}
	if success != 1 || conflict != 1 {
		t.Fatal("duplicate return allowed", success, conflict)
	}
	for _, sql := range []string{`UPDATE app.sales_return_items SET refund_mmk=0`, `DELETE FROM app.purchase_returns WHERE status='POSTED'`, `DELETE FROM app.damaged_products`, `DELETE FROM app.missing_products`, `UPDATE app.stock_operations SET result='{}'`} {
		if _, err = conn.Exec(ctx, sql); err == nil {
			t.Fatal("posted return/issue mutable", sql)
		}
	}

	for _, q := range []string{`UPDATE app.sale_item_batches SET unit_cost_mmk=0 WHERE sale_item_id IN(SELECT id FROM app.sale_items WHERE sale_id IN(SELECT id FROM app.sales WHERE status='POSTED'))`, `UPDATE app.sales SET invoice_document='{}' WHERE status='POSTED'`, `UPDATE app.inventory SET sellable_quantity=100`} {
		if _, err = conn.Exec(ctx, q); err == nil {
			t.Fatal("immutable financial history changed", q)
		}
	}
}
