package purchasing_test

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
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/purchasing"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
)

func TestPurchasingIntegration(t *testing.T) {
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

	_, err = conn.Exec(ctx, `INSERT INTO app.suppliers(id,code,name) VALUES('00000000-0000-0000-0000-000000000001','SUP','Supplier'); INSERT INTO app.products(id,sku,name,base_unit_code) VALUES('00000000-0000-0000-0000-000000000002','TEA','Tea','BOTTLE'); INSERT INTO app.product_units(product_id,unit_code,units_per_pack,is_default_purchase,is_default_sale) VALUES('00000000-0000-0000-0000-000000000002','CARTON',12,true,true)`)
	if err != nil {
		t.Fatal(err)
	}
	supplier := "00000000-0000-0000-0000-000000000001"
	rate := func(value, date string) map[string]any {
		return call("POST", "/exchange-rates", map[string]any{"currency_code": "INR", "mmk_per_unit": value, "effective_at": date, "source": "Supplier quotation"}, owner, 201)
	}
	jan := rate("25", "2026-01-01T00:00:00Z")
	input := func(key, number string) map[string]any {
		return map[string]any{"request_id": key, "purchase_number": number, "supplier_id": supplier, "supplier_invoice_number": number, "purchased_at": "2026-01-15T00:00:00Z", "due_date": "2026-02-15", "currency_code": "INR", "mmk_per_unit": "25", "exchange_rate_id": jan["id"], "items": []map[string]any{{"product_id": "00000000-0000-0000-0000-000000000002", "unit_code": "CARTON", "quantity": "2", "units_per_pack": "12", "unit_price_original": "5000", "discount_original": "0", "tax_original": "0"}}}
	}
	body := input("10000000-0000-0000-0000-000000000001", "JAN-001")
	call("GET", "/purchases", nil, "", 401)
	call("POST", "/purchases", body, staff, 403)
	p := call("POST", "/purchases", body, owner, 201)
	id := p["id"].(string)
	if p["total_original"] != "10000.0000" || p["total_mmk"] != "250000.0000" || p["status"] != "POSTED" {
		t.Fatal("conversion", p)
	}
	if p["items"].([]any)[0].(map[string]any)["base_quantity"] != "24.000000" {
		t.Fatal("packaging snapshot")
	}
	retry := call("POST", "/purchases", body, owner, 200)
	if retry["id"] != id {
		t.Fatal("duplicate retry")
	}
	body["notes"] = "changed"
	call("POST", "/purchases", body, owner, 409)
	delete(body, "notes")
	march := rate("27", "2026-03-01T00:00:00Z")
	body2 := input("10000000-0000-0000-0000-000000000002", "MAR-001")
	body2["purchased_at"] = "2026-03-15T00:00:00Z"
	body2["due_date"] = "2026-04-15"
	body2["exchange_rate_id"] = march["id"]
	body2["mmk_per_unit"] = "27"
	call("POST", "/purchases", body2, owner, 201)
	historical := call("GET", "/purchases/"+id, nil, owner, 200)
	if historical["total_mmk"] != "250000.0000" || historical["mmk_per_unit"] != "25.0000000000" {
		t.Fatal("history changed", historical)
	}
	balance := call("GET", "/suppliers/"+supplier+"/balance", nil, owner, 200)
	if balance["total_outstanding_mmk"] != "520000.0000" {
		t.Fatal("balance", balance)
	}
	// Balances subtract posted allocations at the purchase's historical rate, not today's quote.
	_, err = conn.Exec(ctx, `WITH payment AS (INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,supplier_id,paid_at,recorded_by) SELECT 'PAY-JAN','OUT','CASH','MMK',50000,1,$1,now(),id FROM app.users WHERE username='owner' RETURNING id) INSERT INTO app.payment_allocations(payment_id,purchase_id,settlement_mmk,applied_mmk,applied_original) SELECT id,$2,50000,50000,2000 FROM payment`, supplier, id)
	if err != nil {
		t.Fatal(err)
	}
	_, err = conn.Exec(ctx, `UPDATE app.payments SET status='POSTED',posted_at=now() WHERE payment_number='PAY-JAN'`)
	if err != nil {
		t.Fatal(err)
	}
	balance = call("GET", "/suppliers/"+supplier+"/balance", nil, owner, 200)
	if balance["total_outstanding_mmk"] != "470000.0000" {
		t.Fatal("settled balance", balance)
	}
	paid := call("GET", "/purchases/"+id, nil, owner, 200)
	if paid["outstanding_original"] != "8000.0000" || paid["amount_paid_mmk"] != "50000.0000" {
		t.Fatal("purchase payment", paid)
	}
	for _, sql := range []string{`UPDATE app.exchange_rates SET mmk_per_unit=99`, `UPDATE app.purchases SET mmk_per_unit=99`, `UPDATE app.purchase_items SET unit_price_original=99`, `UPDATE app.purchase_amounts SET amount_original=99`} {
		if _, e := conn.Exec(ctx, sql); e == nil {
			t.Fatal("history mutable", sql)
		}
	}
	_, err = conn.Exec(ctx, `UPDATE app.products SET name='Renamed tea';UPDATE app.product_units SET units_per_pack=24`)
	if err != nil {
		t.Fatal(err)
	}
	historical = call("GET", "/purchases/"+id, nil, owner, 200)
	line := historical["items"].([]any)[0].(map[string]any)
	if line["product_name"] != "Tea" || line["units_per_pack"] != "12.000000" {
		t.Fatal("catalog changed history")
	}
	bad := input("10000000-0000-0000-0000-000000000003", "BAD")
	call("POST", "/purchases", bad, owner, 409) // stale packaging
	bad["items"].([]map[string]any)[0]["units_per_pack"] = "24"
	bad["mmk_per_unit"] = "NaN"
	call("POST", "/purchases", bad, owner, 400)
	bad["mmk_per_unit"] = "25.00000000001"
	call("POST", "/purchases", bad, owner, 400)
	bad["mmk_per_unit"] = "25"
	bad["exchange_rate_id"] = march["id"]
	call("POST", "/purchases", bad, owner, 400)
	bad["mmk_per_unit"] = "27"
	call("POST", "/purchases", bad, owner, 400) // future quote
	bad["currency_code"] = "MMK"
	bad["exchange_rate_id"] = ""
	call("POST", "/purchases", bad, owner, 400)
	bad["mmk_per_unit"] = "1"
	bad["items"].([]map[string]any)[0]["discount_original"] = "99999"
	call("POST", "/purchases", bad, owner, 400)
	if got := call("GET", "/purchases?q=BAD", nil, owner, 200); got["total"] != float64(0) {
		t.Fatal("partial write")
	}
	bad["items"].([]map[string]any)[0]["discount_original"] = "0"
	bad["items"].([]map[string]any)[0]["quantity"] = "0.1"
	bad["items"].([]map[string]any)[0]["unit_price_original"] = "0.123456"
	exact := call("POST", "/purchases", bad, owner, 201)
	if exact["total_original"] != "0.0123" || exact["total_mmk"] != "0.0123" {
		t.Fatal("precision", exact)
	}
	grant := func(codes ...string) {
		t.Helper()
		for _, code := range codes {
			_, e := conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,$1,o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner' ON CONFLICT DO NOTHING`, code)
			if e != nil {
				t.Fatal(e)
			}
		}
	}
	grant("purchases.view", "suppliers.view")
	hidden := call("GET", "/purchases/"+id, nil, staff, 200)
	if _, ok := hidden["total_original"]; ok {
		t.Fatal("cost leaked")
	}
	if _, ok := hidden["items"].([]any)[0].(map[string]any)["unit_price_original"]; ok {
		t.Fatal("line cost leaked")
	}
	call("GET", "/suppliers/"+supplier+"/balance", nil, staff, 403)
	call("GET", "/purchase-options?kind=products", nil, staff, 403)
	grant("purchases.create", "purchases.view_cost")
	manual := input("10000000-0000-0000-0000-000000000004", "MANUAL")
	manual["exchange_rate_id"] = ""
	manual["items"].([]map[string]any)[0]["units_per_pack"] = "24"
	call("POST", "/purchases", manual, staff, 403)
	manual["exchange_rate_id"] = jan["id"]
	call("POST", "/purchases", manual, staff, 201)
	call("POST", "/exchange-rates", map[string]any{}, staff, 403)
	call("POST", "/currencies", map[string]any{"code": "EUR", "name": "Euro", "minor_units": 2}, staff, 403)
	call("POST", "/currencies", map[string]any{"code": "EUR", "name": "Euro", "minor_units": 2}, owner, 201)
	call("POST", "/currencies", map[string]any{"code": "EUR", "name": "Euro", "minor_units": 2}, owner, 409)
	call("GET", "/purchases?page_size=101", nil, owner, 400)
	if got := call("GET", "/purchases?currency=INR&page_size=1", nil, owner, 200); got["total"] != float64(3) || len(got["purchases"].([]any)) != 1 {
		t.Fatal("pagination", got)
	}
	var audits int
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.audit_logs WHERE entity_type='purchases' AND entity_id=$1`, id).Scan(&audits); err != nil || audits != 1 {
		t.Fatal("audit/idempotency", audits, err)
	}
	concurrent := input("10000000-0000-0000-0000-000000000005", "RACE")
	concurrent["items"].([]map[string]any)[0]["units_per_pack"] = "24"
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); codes <- raw("POST", "/purchases", concurrent, owner).Code }()
	}
	wg.Wait()
	close(codes)
	counts := map[int]int{}
	for code := range codes {
		counts[code]++
	}
	if counts[201] != 1 || counts[200] != 1 {
		t.Fatal("concurrent retry", counts)
	}

}
