package finance_test

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
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/finance"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/pos"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/purchasing"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/receiving"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestManualStockAccountsIntegration(t *testing.T) {
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
	receiving.New(pool).Register(r, a)
	purchasing.New(pool).Register(r, a)
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

	call("GET", "/accounts", nil, staff, 403)
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES('00000000-0000-0000-0000-000000000002','payments.manage','00000000-0000-0000-0000-000000000001')`)
	if err != nil {
		t.Fatal(err)
	}
	call("GET", "/accounts", nil, staff, 403)
	if w := raw("GET", "/accounts/options", nil, staff); w.Code != 200 {
		t.Fatal("payment operators need account choices")
	}
	call("POST", "/accounts", map[string]any{}, staff, 403)
	call("GET", "/creditors", nil, staff, 403)
	call("POST", "/creditors", map[string]any{}, staff, 403)
	call("POST", "/creditors/00000000-0000-0000-0000-000000000001/repayments", map[string]any{}, staff, 403)
	call("PATCH", "/accounts/00000000-0000-0000-0000-000000000001", map[string]any{}, staff, 403)
	seq := 1000
	next := func() string { seq++; return fmt.Sprintf("10000000-0000-0000-0000-%012d", seq) }
	scalar := func(sql string, args ...any) string {
		t.Helper()
		var v string
		if e := conn.QueryRow(ctx, sql, args...).Scan(&v); e != nil {
			t.Fatal(e)
		}
		return v
	}
	entry := map[string]any{"request_id": next(), "product_id": "00000000-0000-0000-0000-000000000020", "warehouse_id": "00000000-0000-0000-0000-000000000012", "unit_code": "CARTON", "quantity": "2", "unit_cost_mmk": "100.125", "retail_price_mmk": "150", "wholesale_price_mmk": "140", "received_at": time.Now().Add(-time.Hour).Format(time.RFC3339), "expires_on": "", "reason": "Opening count"}
	entry["version"] = scalar("SELECT version::text FROM app.products WHERE id=$1", entry["product_id"])
	call("POST", "/inventory/manual-stock", entry, staff, 403)
	first := call("POST", "/inventory/manual-stock", entry, owner, 201)
	repeat := call("POST", "/inventory/manual-stock", entry, owner, 201)
	if first["id"] != repeat["id"] {
		t.Fatal("manual retry duplicated")
	}
	if v := scalar("SELECT i.available_quantity::text FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id WHERE b.manual_stock_entry_id=$1", first["id"]); v != "24.000000" {
		t.Fatal(v)
	}
	if v := scalar("SELECT actual_unit_cost_mmk::text FROM app.batches WHERE manual_stock_entry_id=$1", first["id"]); v != "100.12500000" {
		t.Fatal(v)
	}
	if v := scalar("SELECT retail_price_mmk::text FROM app.warehouse_prices WHERE product_id=$1 AND unit_code='CARTON'", entry["product_id"]); v != "1800.0000" {
		t.Fatal(v)
	}
	entry["quantity"] = "3"
	call("POST", "/inventory/manual-stock", entry, owner, 409)
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT '00000000-0000-0000-0000-000000000002',code,'00000000-0000-0000-0000-000000000001' FROM app.permissions ON CONFLICT DO NOTHING`)
	if err != nil {
		t.Fatal(err)
	}
	call("POST", "/inventory/manual-stock", entry, staff, 403)
	account := call("POST", "/accounts", map[string]any{"request_id": next(), "name": "KBZ operating", "bank": "KBZ", "reference": "Test"}, owner, 201)["id"].(string)
	post := func(kind, amount, date string) map[string]any {
		return map[string]any{"request_id": next(), "account_id": account, "kind": kind, "amount_mmk": amount, "sender": "External sender", "description": "Test entry", "occurred_at": date, "reverses_id": ""}
	}
	yesterday := time.Now().Add(-24 * time.Hour).Format(time.RFC3339)
	deposit := post("EXTERNAL_DEPOSIT", "1000.1234", yesterday)
	deposited := call("POST", "/accounts/entries", deposit, owner, 201)
	call("POST", "/accounts/entries", deposit, owner, 201)
	balance := func(want string) {
		t.Helper()
		if v := scalar("SELECT sum(amount_mmk)::text FROM app.account_entries WHERE account_id=$1", account); v != want {
			t.Fatalf("balance %s want %s", v, want)
		}
	}
	balance("1000.1234")
	personal := post("PERSONAL_EXPENSE", "100", time.Now().Add(-23*time.Hour).Format(time.RFC3339))
	call("POST", "/accounts/entries", personal, owner, 201)
	balance("900.1234")
	// Concurrent retries create one ledger row, and independent deposits cannot lose updates.
	concurrentAccount := call("POST", "/accounts", map[string]any{"request_id": next(), "name": "Yoma concurrent", "bank": "Yoma", "reference": ""}, owner, 201)["id"].(string)
	concurrent := post("EXTERNAL_DEPOSIT", "10", yesterday)
	concurrent["account_id"] = concurrentAccount
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); codes <- raw("POST", "/accounts/entries", concurrent, owner).Code }()
	}
	wg.Wait()
	close(codes)
	for code := range codes {
		if code != 201 {
			t.Fatal("concurrent deposit", code)
		}
	}
	if v := scalar("SELECT sum(amount_mmk)::text FROM app.account_entries WHERE account_id=$1", concurrentAccount); v != "10.0000" {
		t.Fatal(v)
	}

	reverseDeposit := post("REVERSAL", "0", time.Now().Format(time.RFC3339))
	reverseDeposit["account_id"] = concurrentAccount
	reverseDeposit["reverses_id"] = scalar("SELECT id::text FROM app.account_entries WHERE request_id=$1", concurrent["request_id"])
	call("POST", "/accounts/entries", reverseDeposit, owner, 201)
	call("POST", "/accounts/entries", reverseDeposit, owner, 201)
	if v := scalar("SELECT sum(amount_mmk)::text FROM app.account_entries WHERE account_id=$1", concurrentAccount); v != "0.0000" {
		t.Fatal("reversal retry", v)
	}
	_, err = conn.Exec(ctx, `UPDATE app.purchases SET status='POSTED',posted_at=now() WHERE id='00000000-0000-0000-0000-000000000040'`)
	if err != nil {
		t.Fatal(err)
	}
	supplierPay := map[string]any{"request_id": next(), "correction_version": "0", "amount": "1", "method_code": "CASH", "paid_at": time.Now().Add(time.Hour).Format(time.RFC3339), "reference_number": "", "bank_account": "", "notes": "", "account_id": concurrentAccount}
	call("POST", "/purchases/00000000-0000-0000-0000-000000000040/payments", supplierPay, owner, 409)
	funding := post("EXTERNAL_DEPOSIT", "100", time.Now().Add(-time.Minute).Format(time.RFC3339Nano))
	funding["account_id"] = concurrentAccount
	call("POST", "/accounts/entries", funding, owner, 201)
	// A stable past timestamp later than the fixture purchase avoids a future-dated cash movement.
	supplierPay["paid_at"] = time.Now().Format(time.RFC3339Nano)
	call("POST", "/purchases/00000000-0000-0000-0000-000000000040/payments", supplierPay, owner, 200)
	if v := scalar("SELECT sum(amount_mmk)::text FROM app.account_entries WHERE account_id=$1", concurrentAccount); v != "75.0000" {
		t.Fatal("historical INR account conversion", v)
	}
	category := scalar("SELECT id::text FROM app.expense_categories LIMIT 1")
	expense := map[string]any{"request_id": next(), "category_id": category, "description": "Business rent", "incurred_on": time.Now().Add(-time.Hour).Format("2006-01-02"), "amount_mmk": "50", "notes": "", "paid_now": true, "method": "BANK_TRANSFER", "reference": "", "account_id": account}
	withoutAccount := map[string]any{}
	for k, v := range expense {
		withoutAccount[k] = v
	}
	withoutAccount["request_id"] = next()
	delete(withoutAccount, "account_id")
	call("POST", "/expenses", withoutAccount, owner, 409)
	if v := scalar("SELECT count(*)::text FROM app.expenses WHERE request_id=$1", withoutAccount["request_id"]); v != "0" {
		t.Fatal("payment validation did not roll back expense")
	}
	saved := call("POST", "/expenses", expense, owner, 201)
	balance("850.1234")
	call("POST", "/expenses", expense, owner, 201)
	balance("850.1234")
	call("POST", "/expenses/"+saved["id"].(string)+"/reverse", map[string]any{"request_id": next(), "reason": "Correction"}, owner, 201)
	balance("900.1234")
	reconcile := post("BALANCE_ADJUSTMENT", "925", time.Now().Format(time.RFC3339))
	call("POST", "/accounts/entries", reconcile, owner, 201)
	balance("925.0000")
	call("POST", "/accounts/entries", post("EXTERNAL_DEPOSIT", "10", yesterday), owner, 409)
	// Failure in audit must roll back money, requests and stock as one unit.
	_, err = conn.Exec(ctx, `CREATE FUNCTION app.test_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test audit failure'; END $$;CREATE TRIGGER test_fail BEFORE INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.test_fail_audit()`)
	if err != nil {
		t.Fatal(err)
	}
	call("POST", "/accounts/entries", post("BALANCE_ADJUSTMENT", "900", time.Now().Format(time.RFC3339)), owner, 503)
	entry["request_id"] = next()
	entry["version"] = scalar("SELECT version::text FROM app.products WHERE id=$1", entry["product_id"])
	call("POST", "/inventory/manual-stock", entry, owner, 503)
	balance("925.0000")
	_, err = conn.Exec(ctx, "DROP TRIGGER test_fail ON app.audit_logs")
	if err != nil {
		t.Fatal(err)
	}
	if v := scalar("SELECT count(*)::text FROM app.manual_stock_entries"); v != "1" {
		t.Fatal("stock audit rollback", v)
	}
	if v := scalar("SELECT count(*)::text FROM app.expenses WHERE description='Test entry'"); v != "0" {
		t.Fatal("personal expense leaked into profit")
	}
	if _, err = conn.Exec(ctx, "UPDATE app.account_entries SET amount_mmk=0 WHERE id=$1", deposited["id"]); err == nil {
		t.Fatal("ledger mutated")
	}
	call("GET", "/accounts/history?account_id="+account, nil, owner, 200)
	// Metadata edits and archival never rewrite the financial ledger.
	update := map[string]any{"request_id": next(), "version": 1, "name": "KBZ renamed", "bank": "KBZ updated", "reference": "New reference", "is_active": true}
	call("PATCH", "/accounts/"+account, update, owner, 201)
	call("PATCH", "/accounts/"+account, update, owner, 201)
	balance("925.0000")
	update["request_id"] = next()
	call("PATCH", "/accounts/"+account, update, owner, 409)
	update["version"] = 2
	update["is_active"] = false
	call("PATCH", "/accounts/"+account, update, owner, 201)
	if v := scalar("SELECT version::text FROM app.money_accounts WHERE id=$1", account); v != "3" {
		t.Fatal("metadata retry or archive version", v)
	}
	options := raw("GET", "/accounts/options", nil, owner)
	if strings.Contains(options.Body.String(), account) {
		t.Fatal("archived account offered for payment")
	}
	call("POST", "/accounts/entries", post("EXTERNAL_DEPOSIT", "10", time.Now().Format(time.RFC3339)), owner, 409)
	supplierPay["request_id"] = next()
	supplierPay["account_id"] = account
	supplierPay["paid_at"] = time.Now().Format(time.RFC3339)
	call("POST", "/purchases/00000000-0000-0000-0000-000000000040/payments", supplierPay, owner, 409)
	call("GET", "/accounts/history?account_id="+account, nil, owner, 200)
	if _, err = conn.Exec(ctx, "DELETE FROM app.money_accounts WHERE id=$1", account); err == nil {
		t.Fatal("account history can be deleted")
	}
	update["request_id"] = next()
	update["version"] = 3
	update["is_active"] = true
	_, err = conn.Exec(ctx, "CREATE TRIGGER test_fail BEFORE INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.test_fail_audit()")
	if err != nil {
		t.Fatal(err)
	}
	call("PATCH", "/accounts/"+account, update, owner, 503)
	if v := scalar("SELECT is_active::text FROM app.money_accounts WHERE id=$1", account); v != "false" {
		t.Fatal("account audit failure did not roll back")
	}
	_, err = conn.Exec(ctx, "DROP TRIGGER test_fail ON app.audit_logs")
	if err != nil {
		t.Fatal(err)
	}
	call("PATCH", "/accounts/"+account, update, owner, 201)
	balance("925.0000")
	// Two editors cannot silently overwrite one another.
	editA := map[string]any{"request_id": next(), "version": 1, "name": "Concurrent A", "bank": "", "reference": "", "is_active": true}
	editB := map[string]any{"request_id": next(), "version": 1, "name": "Concurrent B", "bank": "", "reference": "", "is_active": true}
	editCodes := make(chan int, 2)
	for _, data := range []map[string]any{editA, editB} {
		go func(d map[string]any) { editCodes <- raw("PATCH", "/accounts/"+concurrentAccount, d, owner).Code }(data)
	}
	firstCode, secondCode := <-editCodes, <-editCodes
	if !((firstCode == 201 && secondCode == 409) || (firstCode == 409 && secondCode == 201)) {
		t.Fatalf("concurrent metadata updates: %d, %d", firstCode, secondCode)
	}
	// Archival must not break source-linked financial corrections.
	expense["request_id"] = next()
	expense["account_id"] = concurrentAccount
	archivedExpense := call("POST", "/expenses", expense, owner, 201)
	archive := map[string]any{"request_id": next(), "version": 2, "name": "Archived bank", "bank": "", "reference": "", "is_active": false}
	call("PATCH", "/accounts/"+concurrentAccount, archive, owner, 201)
	call("POST", "/expenses/"+archivedExpense["id"].(string)+"/reverse", map[string]any{"request_id": next(), "reason": "Correct archived account payment"}, owner, 201)
	if v := scalar("SELECT sum(amount_mmk)::text FROM app.account_entries WHERE account_id=$1", concurrentAccount); v != "75.0000" {
		t.Fatal("archived account source reversal lost balance", v)
	}
	t.Run("unified_funding_and_third_party_payables", func(t *testing.T) {
		creditor := call("POST", "/creditors", map[string]any{"request_id": next(), "name": "Mother", "contact": "Family"}, owner, 201)["id"].(string)
		empty := call("POST", "/accounts", map[string]any{"request_id": next(), "name": "My Cash", "bank": "Cash", "reference": ""}, owner, 201)["id"].(string)
		funded := func() string {
			return scalar("SELECT coalesce(sum(amount_mmk),0)::numeric(20,4)::text FROM app.account_entries WHERE creditor_id=$1", creditor)
		}
		cash := func() string {
			return scalar("SELECT coalesce(sum(amount_mmk),0)::numeric(20,4)::text FROM app.account_entries WHERE account_id=$1", empty)
		}
		supplierPay["request_id"] = next()
		supplierPay["account_id"] = empty
		supplierPay["paid_at"] = time.Now().Format(time.RFC3339Nano)
		call("POST", "/purchases/00000000-0000-0000-0000-000000000040/payments", supplierPay, owner, 409)
		supplierPay["account_id"] = ""
		supplierPay["creditor_id"] = creditor
		call("POST", "/purchases/00000000-0000-0000-0000-000000000040/payments", supplierPay, owner, 200)
		call("POST", "/purchases/00000000-0000-0000-0000-000000000040/payments", supplierPay, owner, 200)
		if funded() != "25.0000" || cash() != "0.0000" {
			t.Fatal("supplier third-party funding or duplicate changed wrong balance", funded(), cash())
		}
		expense["request_id"] = next()
		expense["account_id"] = ""
		expense["creditor_id"] = creditor
		expense["description"] = "Mother paid business cost"
		thirdExpense := call("POST", "/expenses", expense, owner, 201)
		call("POST", "/expenses", expense, owner, 201)
		if funded() != "75.0000" || cash() != "0.0000" {
			t.Fatal("expense funding did not create separate debt")
		}
		repay := map[string]any{"request_id": next(), "account_id": empty, "amount_mmk": "30", "method": "CASH", "paid_at": scalar(`SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`), "reference": "Partial repayment", "notes": ""}
		call("POST", "/creditors/"+creditor+"/repayments", repay, owner, 409)
		deposit := post("EXTERNAL_DEPOSIT", "100", time.Now().Add(-time.Minute).Format(time.RFC3339Nano))
		deposit["account_id"] = empty
		call("POST", "/accounts/entries", deposit, owner, 201)
		firstRepayment := call("POST", "/creditors/"+creditor+"/repayments", repay, owner, 201)
		call("POST", "/creditors/"+creditor+"/repayments", repay, owner, 201)
		if funded() != "45.0000" || cash() != "70.0000" {
			t.Fatal("repayment was not atomic/deduplicated", funded(), cash())
		}
		// Concurrent debit requests cannot spend the same available funds twice.
		debitA := post("PERSONAL_EXPENSE", "60", time.Now().Format(time.RFC3339Nano))
		debitA["account_id"] = empty
		debitB := post("PERSONAL_EXPENSE", "60", time.Now().Format(time.RFC3339Nano))
		debitB["account_id"] = empty
		results := make(chan int, 2)
		for _, d := range []map[string]any{debitA, debitB} {
			go func(body map[string]any) { results <- raw("POST", "/accounts/entries", body, owner).Code }(d)
		}
		x, y := <-results, <-results
		if !((x == 201 && y == 409) || (x == 409 && y == 201)) || cash() != "10.0000" {
			t.Fatalf("concurrent overspend: %d %d balance %s", x, y, cash())
		}
		// Audit failure rolls back both sides of a repayment and its request identity.
		_, err = conn.Exec(ctx, "CREATE TRIGGER test_fail BEFORE INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.test_fail_audit()")
		if err != nil {
			t.Fatal(err)
		}
		repay["request_id"] = next()
		repay["amount_mmk"] = "5"
		repay["paid_at"] = scalar(`SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`)
		call("POST", "/creditors/"+creditor+"/repayments", repay, owner, 503)
		if cash() != "10.0000" || funded() != "45.0000" {
			t.Fatal("repayment audit rollback")
		}
		_, err = conn.Exec(ctx, "DROP TRIGGER test_fail ON app.audit_logs")
		if err != nil {
			t.Fatal(err)
		}
		// A funded expense cannot be reversed past the outstanding third-party debt.
		call("POST", "/expenses/"+thirdExpense["id"].(string)+"/reverse", map[string]any{"request_id": next(), "reason": "Already partly repaid"}, owner, 409)
		deposit["request_id"] = next()
		deposit["occurred_at"] = time.Now().Format(time.RFC3339Nano)
		call("POST", "/accounts/entries", deposit, owner, 201)
		repay["request_id"] = next()
		repay["amount_mmk"] = "45"
		repay["paid_at"] = scalar(`SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`)
		call("POST", "/creditors/"+creditor+"/repayments", repay, owner, 201)
		if funded() != "0.0000" || cash() != "65.0000" {
			t.Fatal("full repayment", funded(), cash())
		}
		repay["request_id"] = next()
		repay["amount_mmk"] = "1"
		call("POST", "/creditors/"+creditor+"/repayments", repay, owner, 409)
		// Source reversal cancels an unpaid third-party liability without touching business cash.
		expense["request_id"] = next()
		fresh := call("POST", "/expenses", expense, owner, 201)
		call("POST", "/expenses/"+fresh["id"].(string)+"/reverse", map[string]any{"request_id": next(), "reason": "Duplicate expense"}, owner, 201)
		if funded() != "0.0000" || cash() != "65.0000" {
			t.Fatal("third-party source reversal")
		}
		// Removing every account selection is rejected even on an installation with cash available.
		expense["request_id"] = next()
		delete(expense, "account_id")
		delete(expense, "creditor_id")
		call("POST", "/expenses", expense, owner, 409)

		reversal := map[string]any{"request_id": next(), "reason": "Repayment entered twice"}
		path := "/creditors/" + creditor + "/repayments/" + firstRepayment["id"].(string) + "/reverse"
		call("POST", path, reversal, owner, 201)
		call("POST", path, reversal, owner, 201)
		if funded() != "30.0000" || cash() != "95.0000" {
			t.Fatal("repayment reversal did not restore both ledgers", funded(), cash())
		}
		reversal["request_id"] = next()
		call("POST", path, reversal, owner, 409)
		call("GET", "/creditors/"+creditor+"/history", nil, owner, 200)
	})

}
