package finance_test

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/finance"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/pos"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

func TestFinanceIntegration(t *testing.T) {
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
	finance.New(pool).Register(r, a)
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

	if _, err = conn.Exec(ctx, `UPDATE app.sales SET status='POSTED',posted_at=now() WHERE id='00000000-0000-0000-0000-000000000080'`); err != nil {
		t.Fatal(err)
	}
	call("GET", "/finance/profit", nil, staff, 403)
	report := call("GET", "/finance/profit", nil, owner, 200)
	if report["revenue_mmk"] != "80000.0000" || report["cogs_mmk"] != "60000.0000" || report["gross_profit_mmk"] != "20000.0000" || report["net_profit_mmk"] != "20000.0000" {
		t.Fatal("landed profit", report)
	}

	t.Run("dashboard snapshot and permission boundaries", func(t *testing.T) {
		call("GET", "/dashboard", nil, staff, 403)
		dashboard := call("GET", "/dashboard", nil, owner, 200)
		if dashboard["sales"].(map[string]any)["today_mmk"] != "80000.0000" || dashboard["profit"].(map[string]any)["month"].(map[string]any)["net_profit_mmk"] != "20000.0000" {
			t.Fatal(dashboard)
		}
		if dashboard["inventory_value"].(map[string]any)["amount_mmk"] != nil {
			t.Fatal("unfinalized inventory must not be valued", dashboard)
		}
		if dashboard["customer_debt_mmk"] != "80000.0000" || dashboard["supplier_debt_mmk"] != "0.0000" {
			t.Fatal("ledger balances", dashboard)
		}
		if _, err = conn.Exec(ctx, `UPDATE app.batches SET expires_on=app.business_date()+10,finalized_at=now(); UPDATE app.products SET minimum_stock=20 WHERE sku='P-1'; UPDATE app.purchases SET status='POSTED',posted_at=now();`); err != nil {
			t.Fatal(err)
		}
		dashboard = call("GET", "/dashboard", nil, owner, 200)
		if dashboard["inventory_value"].(map[string]any)["amount_mmk"] != "300000.0000" || dashboard["supplier_debt_mmk"] != "250000.0000" {
			t.Fatal("historical landed value and supplier debt", dashboard)
		}
		for _, key := range []string{"low_stock", "expiring", "damaged"} {
			if dashboard[key].(map[string]any)["total"] != float64(1) {
				t.Fatal(key, dashboard)
			}
		}
		grant := func(code string) {
			t.Helper()
			if _, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002',$1,'00000000-0000-0000-0000-000000000001')`, code); err != nil {
				t.Fatal(err)
			}
		}
		grant("dashboard.view")
		limited := call("GET", "/dashboard", nil, staff, 200)
		for _, key := range []string{"sales", "profit", "inventory_value", "customer_debt_mmk", "supplier_debt_mmk", "low_stock", "expiring", "damaged"} {
			if _, exists := limited[key]; exists {
				t.Fatal("leaked", key)
			}
		}
		if len(limited["recent"].([]any)) != 0 {
			t.Fatal("leaked transactions", limited)
		}
		grant("inventory.view")
		limited = call("GET", "/dashboard", nil, staff, 200)
		if _, exists := limited["low_stock"]; !exists {
			t.Fatal("missing permitted stock")
		}
		if _, exists := limited["inventory_value"]; exists {
			t.Fatal("leaked landed value")
		}
		grant("sales.view")
		limited = call("GET", "/dashboard", nil, staff, 200)
		if _, exists := limited["profit"]; exists {
			t.Fatal("leaked profit")
		}
		if len(limited["recent"].([]any)) != 1 {
			t.Fatal("sale-only recent", limited)
		}
		for _, row := range limited["recent"].([]any) {
			if row.(map[string]any)["kind"] != "Sale" {
				t.Fatal(row)
			}
		}
	})
	var category, today string
	if err = conn.QueryRow(ctx, `SELECT id::text,app.business_date()::text FROM app.expense_categories WHERE name='Rent'`).Scan(&category, &today); err != nil {
		t.Fatal(err)
	}
	expense := map[string]any{"request_id": "90000000-0000-0000-0000-000000000001", "category_id": category, "description": "Rent test", "incurred_on": today, "amount_mmk": "5000.0001", "notes": "Exact amount", "paid_now": true, "method": "CASH", "reference": "Receipt"}
	call("POST", "/expenses", expense, staff, 403)
	snapshot := func() string {
		t.Helper()
		var result string
		if err = conn.QueryRow(ctx, `SELECT jsonb_build_object('expenses',(SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM app.expenses e),'payments',(SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM app.payments p),'allocations',(SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM app.payment_allocations a),'reversals',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM app.expense_reversals r),'audit',(SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM app.audit_logs a))::text`).Scan(&result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	before := snapshot()
	if _, err = conn.Exec(ctx, `CREATE FUNCTION app.test_finance_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected'; END $$;CREATE TRIGGER fail_finance AFTER INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.test_finance_failure()`); err != nil {
		t.Fatal(err)
	}
	call("POST", "/expenses", expense, owner, 503)
	if snapshot() != before {
		t.Fatal("expense failed partially")
	}
	if _, err = conn.Exec(ctx, `DROP TRIGGER fail_finance ON app.audit_logs`); err != nil {
		t.Fatal(err)
	}
	saved := call("POST", "/expenses", expense, owner, 201)
	call("POST", "/expenses", expense, owner, 201)
	report = call("GET", "/finance/profit", nil, owner, 200)
	if report["expenses_mmk"] != "5000.0001" || report["net_profit_mmk"] != "14999.9999" {
		t.Fatal("exact net profit", report)
	}
	expense["amount_mmk"] = "5"
	call("POST", "/expenses", expense, owner, 409)
	reverse := map[string]any{"request_id": "90000000-0000-0000-0000-000000000002", "reason": "Duplicate entry correction"}
	path := "/expenses/" + saved["id"].(string) + "/reverse"
	before = snapshot()
	if _, err = conn.Exec(ctx, `CREATE TRIGGER fail_finance AFTER INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.test_finance_failure()`); err != nil {
		t.Fatal(err)
	}
	call("POST", path, reverse, owner, 503)
	if snapshot() != before {
		t.Fatal("reversal failed partially")
	}
	if _, err = conn.Exec(ctx, `DROP TRIGGER fail_finance ON app.audit_logs`); err != nil {
		t.Fatal(err)
	}
	call("POST", path, reverse, owner, 201)
	call("POST", path, reverse, owner, 201)
	report = call("GET", "/finance/profit", nil, owner, 200)
	if report["expenses_mmk"] != "0.0000" || report["net_profit_mmk"] != "20000.0000" {
		t.Fatal("reversal profit", report)
	}
	dashboardAfterReversal := call("GET", "/dashboard", nil, owner, 200)
	expenseEvents := map[string]string{}
	for _, row := range dashboardAfterReversal["recent"].([]any) {
		event := row.(map[string]any)
		if event["kind"] == "Expense" || event["kind"] == "Expense reversal" {
			expenseEvents[event["kind"].(string)] = event["amount_mmk"].(string)
		}
	}
	if expenseEvents["Expense"] != "5000.0001" || expenseEvents["Expense reversal"] != "-5000.0001" {
		t.Fatal("dashboard must retain original expense and reversal", expenseEvents)
	}
	var valid bool
	if err = conn.QueryRow(ctx, `SELECT count(*)=1 FROM app.payments p JOIN app.expense_reversal_payments r ON r.offset_payment_id=p.id WHERE p.direction='IN' AND p.status='POSTED' AND p.amount_mmk=5000.0001`).Scan(&valid); err != nil || !valid {
		t.Fatal("payment reversal", err)
	}
	// Unpaid expense is still an operating expense; collections never create revenue twice.
	expense["request_id"] = "90000000-0000-0000-0000-000000000003"
	expense["amount_mmk"] = "30000"
	expense["paid_now"] = false
	call("POST", "/expenses", expense, owner, 201)
	report = call("GET", "/finance/profit", nil, owner, 200)
	if report["net_profit_mmk"] != "-10000.0000" {
		t.Fatal("negative net profit", report)
	}
	ret := map[string]any{"request_id": "90000000-0000-0000-0000-000000000004", "sale_id": "00000000-0000-0000-0000-000000000080", "resolution": "CREDIT", "reason": "Partial return", "method": "CASH", "items": []map[string]any{{"sale_item_batch_id": "00000000-0000-0000-0000-000000000082", "quantity": "1", "disposition": "SELLABLE"}}}
	quote := call("POST", "/returns/sales/preview", ret, owner, 200)
	ret["quote_hash"] = quote["quote_hash"]
	call("POST", "/returns/sales", ret, owner, 200)
	report = call("GET", "/finance/profit", nil, owner, 200)
	if report["revenue_mmk"] != "40000.0000" || report["cogs_mmk"] != "30000.0000" || report["gross_profit_mmk"] != "10000.0000" || report["net_profit_mmk"] != "-20000.0000" {
		t.Fatal("return profit", report)
	}
	empty := call("GET", "/finance/profit?from=2000-01-01&to=2000-01-31", nil, owner, 200)
	if empty["net_profit_mmk"] != "0.0000" {
		t.Fatal("empty date range", empty)
	}
	call("GET", "/finance/profit?from=2026-03-02&to=2026-01-01", nil, owner, 400)
	// Never silently replace missing landed allocations with supplier price or zero profit.
	if _, err = conn.Exec(ctx, `WITH s AS(INSERT INTO app.sales(invoice_number,warehouse_id,pricing_mode,sold_at,created_by) VALUES('UNCOSTED','00000000-0000-0000-0000-000000000012','RETAIL',now(),'00000000-0000-0000-0000-000000000001') RETURNING id) INSERT INTO app.sale_items(sale_id,line_number,product_id,unit_code,units_per_pack,quantity,unit_price_mmk) SELECT id,1,'00000000-0000-0000-0000-000000000020','BOTTLE',1,1,500 FROM s;UPDATE app.sales SET status='POSTED',posted_at=now() WHERE invoice_number='UNCOSTED'`); err != nil {
		t.Fatal(err)
	}
	report = call("GET", "/finance/profit", nil, owner, 200)
	if report["gross_profit_mmk"] != nil || report["net_profit_mmk"] != nil || report["incomplete_cost_sales"] != float64(1) {
		t.Fatal("missing costs silently included", report)
	}
	for _, sql := range []string{`UPDATE app.expenses SET amount_original=1 WHERE posted_at IS NOT NULL`, `DELETE FROM app.expense_reversals`} {
		if _, err = conn.Exec(ctx, sql); err == nil {
			t.Fatal("expense history mutable")
		}
	}
}
