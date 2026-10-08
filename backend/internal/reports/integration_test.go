package reports

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
)

func TestReportsIntegration(t *testing.T) {
	ctx := context.Background()
	conn := testutil.Database(t)
	if err := migrate.Up(ctx, conn, os.DirFS("../../../database/migrations")); err != nil {
		t.Fatal(err)
	}
	fixture, err := os.ReadFile("../../../database/tests/fixture.sql")
	if err != nil {
		t.Fatal(err)
	}
	// Last second of February in Myanmar; timestamps are deliberately UTC.
	seed := strings.ReplaceAll(string(fixture), "now()", "'2020-02-29 17:29:59+00'::timestamptz")
	if _, err = conn.Exec(ctx, seed); err != nil {
		t.Fatal(err)
	}
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := conn.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`UPDATE app.goods_receiving SET status='POSTED',posted_at=now();UPDATE app.sales SET status='POSTED',posted_at=now();UPDATE app.purchases SET status='POSTED',posted_at=now();UPDATE app.batches SET finalized_at='2020-02-29 17:29:59+00';UPDATE app.shipments SET created_at='2020-02-29 17:29:59+00';
 INSERT INTO app.transportation_stages(shipment_id,stage_number,start_location,destination,provider_name,departed_at,transportation_fee_mmk,loading_fee_mmk) VALUES('00000000-0000-0000-0000-000000000050',1,'A','B','Carrier','2020-02-29 17:29:59+00',100.1234,10);
 INSERT INTO app.expenses(id,category_id,description,incurred_at,currency_code,amount_original,mmk_per_unit,recorded_by,status,posted_at) SELECT '10000000-0000-0000-0000-000000000001',id,'Test rent','2020-02-29 17:29:59+00','MMK',5000.0001,1,'00000000-0000-0000-0000-000000000001','POSTED',now() FROM app.expense_categories WHERE name='Rent';
 INSERT INTO app.expense_reversals(expense_id,request_id,request_payload,reason,recorded_by,reversed_at) VALUES('10000000-0000-0000-0000-000000000001',gen_random_uuid(),'{}','Correction','00000000-0000-0000-0000-000000000001','2020-02-29 17:30:00+00');
 INSERT INTO app.damaged_products(id,product_id,batch_id,warehouse_id,quantity,estimated_loss_mmk,reason,occurred_at,recorded_by,disposition) VALUES('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000070','00000000-0000-0000-0000-000000000012',1,30000,'Damage','2020-02-29 17:29:59+00','00000000-0000-0000-0000-000000000001','QUARANTINE');
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,damaged_product_id,idempotency_key,occurred_at,recorded_by) VALUES('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000070','DAMAGE',-1,1,30000,'10000000-0000-0000-0000-000000000002','reports-damage','2020-02-29 17:29:59+00','00000000-0000-0000-0000-000000000001');
 INSERT INTO app.missing_products(id,product_id,batch_id,warehouse_id,quantity,estimated_loss_mmk,reason,occurred_at,recorded_by) VALUES('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000070','00000000-0000-0000-0000-000000000012',1,30000,'Missing','2020-02-29 17:29:59+00','00000000-0000-0000-0000-000000000001');
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,missing_product_id,idempotency_key,occurred_at,recorded_by) VALUES('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000070','MISSING',-1,30000,'10000000-0000-0000-0000-000000000003','reports-missing','2020-02-29 17:29:59+00','00000000-0000-0000-0000-000000000001');`)
	const owner = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	const staff = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA"
	for i, token := range []string{owner, staff} {
		hash := sha256.Sum256([]byte(token))
		exec(`INSERT INTO app.user_sessions(user_id,token_hash,expires_at) VALUES(('00000000-0000-0000-0000-'||lpad($1::int::text,12,'0'))::uuid,$2,now()+interval '1 hour')`, i+1, hash[:])
	}
	gin.SetMode(gin.TestMode)
	router := gin.New()
	Register(router, conn, authz.New(database.New(conn)))
	call := func(path, token string, want int) []byte {
		t.Helper()
		req := httptest.NewRequest("GET", "/api/v1/reports"+path, nil)
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)
		if w.Code != want {
			t.Fatalf("%s got %d want %d: %s", path, w.Code, want, w.Body.String())
		}
		return w.Body.Bytes()
	}
	read := func(id, rangeQuery string) Response {
		t.Helper()
		var response Response
		if err := json.Unmarshal(call("/"+id+rangeQuery, owner, 200), &response); err != nil {
			t.Fatal(err)
		}
		return response
	}
	const feb = "?period=custom&from=2020-02-01&to=2020-02-29"
	const march = "?period=custom&from=2020-03-01&to=2020-03-31"
	metric := func(r Response, key, want string) {
		t.Helper()
		var got string
		if err := json.Unmarshal(r.Summary[key], &got); err != nil || got != want {
			t.Fatalf("%s %s got %s want %s", r.Definition.ID, key, r.Summary[key], want)
		}
	}
	call("", "", 401)
	call("", staff, 403)
	for _, d := range definitions {
		if d.ID == "payments" {
			metric(read(d.ID, feb), "incoming_mmk", "0")
			call("/"+d.ID+feb, staff, 403)
			continue
		}
		r := read(d.ID, feb)
		if r.Total < 1 || len(r.Rows) == 0 {
			t.Fatalf("missing fixture rows for %s: %+v", d.ID, r)
		}
		for _, column := range d.Columns {
			if _, ok := r.Rows[0][column.Key]; !ok {
				t.Errorf("%s missing %s", d.ID, column.Key)
			}
		}
		call("/"+d.ID+feb, staff, 403)
		empty := read(d.ID, "?period=custom&from=2000-01-01&to=2000-01-31")
		if d.ID != "profit-loss" && empty.Total != 0 {
			t.Errorf("nonempty historical report %s", d.ID)
		}
	}
	metric(read("sales", feb), "revenue_mmk", "80000.0000")
	metric(read("purchases", feb), "amount_mmk", "250000.0000")
	metric(read("currency-purchases", feb), "amount_mmk", "250000.0000")
	metric(read("profit-loss", feb), "net_profit_mmk", "14999.9999")
	metric(read("product-profitability", feb), "gross_profit_mmk", "20000.0000")
	metric(read("transportation", feb), "total_mmk", "110.1234")
	metric(read("expenses", march), "amount_mmk", "-5000.0001")
	metric(read("customer-debt", feb), "outstanding_mmk", "80000.0000")
	metric(read("supplier-payables", feb), "outstanding_mmk", "250000.0000")
	inv := read("inventory", march)
	if string(inv.Rows[0]["opening_sellable"]) != `"8.000000"` || string(inv.Rows[0]["closing_available"]) != `"6.000000"` {
		t.Fatal(inv.Rows)
	}
	// Historical exchange-rate edits elsewhere cannot change the saved purchase conversion.
	exec(`INSERT INTO app.exchange_rates(currency_code,mmk_per_unit,effective_at,source,recorded_by) VALUES('INR',999,now(),'report-test','00000000-0000-0000-0000-000000000001')`)
	metric(read("purchases", feb), "amount_mmk", "250000.0000")
	// A collection just after the Myanmar date boundary must not reduce February debt.
	exec(`INSERT INTO app.payments(id,payment_number,direction,method,currency_code,amount_original,mmk_per_unit,customer_id,paid_at,recorded_by) VALUES('10000000-0000-0000-0000-000000000004','REPORT-PAY','IN','CASH','MMK',10000,1,'00000000-0000-0000-0000-000000000011','2020-02-29 17:30:00+00','00000000-0000-0000-0000-000000000001');
 INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) VALUES('10000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000080',10000,10000,10000);
 UPDATE app.payments SET status='POSTED',posted_at=now() WHERE payment_number='REPORT-PAY';`)
	metric(read("payments", march), "incoming_mmk", "10000.0000")
	metric(read("payments", feb), "incoming_mmk", "0")
	metric(read("customer-debt", feb), "outstanding_mmk", "80000.0000")
	metric(read("customer-debt", march), "outstanding_mmk", "70000.0000")
	metric(read("sales", march), "revenue_mmk", "0.0000")
	// Returns belong to their return period, not the original invoice period.
	exec(`INSERT INTO app.sales_returns(id,return_number,sale_id,return_type,returned_at,reason,created_by) VALUES('10000000-0000-0000-0000-000000000005','REPORT-RETURN','00000000-0000-0000-0000-000000000080','CREDIT','2020-03-01 00:00:00+00','Return','00000000-0000-0000-0000-000000000001');
 INSERT INTO app.sales_return_items(id,sales_return_id,sale_id,sale_item_id,sale_item_batch_id,product_id,quantity,refund_mmk,disposition) VALUES('10000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000080','00000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000020',1,40000,'SELLABLE');
 UPDATE app.sales_returns SET status='POSTED',posted_at=now() WHERE return_number='REPORT-RETURN';
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,sales_return_item_id,idempotency_key,occurred_at,recorded_by) VALUES('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000070','SALE_RETURN',1,30000,'10000000-0000-0000-0000-000000000006','report-return','2020-03-01 00:00:00+00','00000000-0000-0000-0000-000000000001');`)
	metric(read("sales", feb), "revenue_mmk", "80000.0000")
	metric(read("sales", march), "revenue_mmk", "-40000.0000")
	metric(read("product-profitability", march), "gross_profit_mmk", "-10000.0000")
	metric(read("profit-loss", march), "net_profit_mmk", "-4999.9999")
	metric(read("customer-debt", march), "outstanding_mmk", "30000.0000")
	if string(read("sales", march).Rows[0]["reference"]) != `"REPORT-RETURN"` {
		t.Fatal("return reference must identify the return")
	}
	metric(read("damage", feb), "estimated_loss_mmk", "60000.0000")
	metric(read("missing", feb), "estimated_loss_mmk", "60000.0000")
	// Withholding profit is safer than falling back to supplier prices for an unallocated sale.
	exec(`INSERT INTO app.sales(id,invoice_number,warehouse_id,pricing_mode,sold_at,created_by) VALUES('10000000-0000-0000-0000-000000000007','REPORT-INCOMPLETE','00000000-0000-0000-0000-000000000012','RETAIL','2020-03-02 00:00:00+00','00000000-0000-0000-0000-000000000001');
 INSERT INTO app.sale_items(sale_id,line_number,product_id,unit_code,units_per_pack,quantity,unit_price_mmk) VALUES('10000000-0000-0000-0000-000000000007',1,'00000000-0000-0000-0000-000000000020','BOTTLE',1,1,40000);
 UPDATE app.sales SET status='POSTED',posted_at=now() WHERE invoice_number='REPORT-INCOMPLETE';`)
	if string(read("product-profitability", march).Summary["gross_profit_mmk"]) != "null" || string(read("profit-loss", march).Summary["net_profit_mmk"]) != "null" {
		t.Fatal("incomplete profit was exposed")
	}

	// Currency groups preserve original amounts; only MMK is combined across currencies.
	exec(`INSERT INTO app.purchases(id,purchase_number,supplier_id,purchased_at,currency_code,mmk_per_unit,created_by) VALUES('10000000-0000-0000-0000-000000000008','REPORT-USD','00000000-0000-0000-0000-000000000010','2020-02-29 17:29:59+00','USD',100,'00000000-0000-0000-0000-000000000001');
 INSERT INTO app.purchase_items(purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original) VALUES('10000000-0000-0000-0000-000000000008',1,'00000000-0000-0000-0000-000000000020','BOTTLE',1,1,7.1234);
 UPDATE app.purchases SET status='POSTED',posted_at=now() WHERE purchase_number='REPORT-USD';
 INSERT INTO app.purchase_returns(id,return_number,purchase_id,returned_at,resolution,reason,created_by) VALUES('10000000-0000-0000-0000-000000000009','REPORT-SUPPLIER-RETURN','00000000-0000-0000-0000-000000000040','2020-03-01 00:00:00+00','SUPPLIER_CREDIT','Return','00000000-0000-0000-0000-000000000001');
 INSERT INTO app.purchase_return_items(id,purchase_return_id,purchase_id,purchase_item_id,product_id,batch_id,quantity,credit_original,credit_mmk,inventory_cost_mmk) VALUES('10000000-0000-0000-0000-000000000010','10000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000040','00000000-0000-0000-0000-000000000041','00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000070',1,1000,25000,30000);
 UPDATE app.purchase_returns SET status='POSTED',posted_at=now() WHERE return_number='REPORT-SUPPLIER-RETURN';
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,purchase_return_item_id,idempotency_key,occurred_at,recorded_by) VALUES('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000070','PURCHASE_RETURN',-1,30000,'10000000-0000-0000-0000-000000000010','report-supplier-return','2020-03-01 00:00:00+00','00000000-0000-0000-0000-000000000001');`)
	currencies := read("currency-purchases", feb)
	if currencies.Total != 2 || string(currencies.Rows[1]["net_original"]) != `"7.1234"` {
		t.Fatal(currencies)
	}
	metric(currencies, "amount_mmk", "250712.3400")
	metric(read("purchases", march), "amount_mmk", "-25000.0000")
	metric(read("supplier-payables", feb), "outstanding_mmk", "250712.3400")
	metric(read("supplier-payables", march), "outstanding_mmk", "225712.3400")

	// Totals describe the whole filtered report, not only its first page.
	first := read("stock-movements", feb+"&page_size=1")
	second := read("stock-movements", feb+"&page_size=1&page=2")
	if first.Total != 4 || len(first.Rows) != 1 || string(first.Rows[0]["id"]) == string(second.Rows[0]["id"]) {
		t.Fatal(first, second)
	}
	metric(first, "movements", "4")
	for _, query := range []string{"?period=bad", "?period=custom&from=2020-02-30&to=2020-03-01", "?page_size=101", "?page=0", "?unexpected=1", "?page=1&page=2"} {
		call("/sales"+query, owner, 400)
	}
	// A reports-only user has no access to business data; grants are checked per request.
	exec(`INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002','reports.view','00000000-0000-0000-0000-000000000001')`)
	if string(call("", staff, 200)) != `{"reports":[]}` {
		t.Fatal("reports-only catalog leaked")
	}
	for _, d := range definitions {
		call("/"+d.ID+feb, staff, 403)
	}
	exec(`INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002','sales.view','00000000-0000-0000-0000-000000000001')`)
	call("/sales"+feb, staff, 200)
	call("/profit-loss"+feb, staff, 403)
	exec(`DELETE FROM app.user_permissions WHERE permission_code='sales.view'`)
	call("/sales"+feb, staff, 403)
	call("/unknown", owner, 404)
	// Every report enforces every member of its policy, not just the reports gate.
	for _, definition := range definitions {
		codes := policies[definition.ID]
		for _, code := range codes {
			exec(`INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002',$1,'00000000-0000-0000-0000-000000000001') ON CONFLICT DO NOTHING`, string(code))
		}
		call("/"+definition.ID+feb, staff, 200)
		for _, code := range codes {
			exec(`DELETE FROM app.user_permissions WHERE user_id='00000000-0000-0000-0000-000000000002' AND permission_code=$1`, string(code))
			call("/"+definition.ID+feb, staff, 403)
			exec(`INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002',$1,'00000000-0000-0000-0000-000000000001')`, string(code))
		}
	}

}
