package testutil

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
	"strings"
	"testing"
)

// WithPaymentAccount makes legacy workflow fixtures explicitly select their seeded cash account.
// Account/funding validation tests deliberately do not use this helper.
func WithPaymentAccount(path string, body any) any {
	eligible := path == "/pos/quote" || path == "/pos/checkout" || path == "/transport-payments" || path == "/expenses" || path == "/returns/sales" || path == "/returns/sales/preview" || path == "/returns/purchases" || path == "/returns/purchases/preview" || ((strings.HasPrefix(path, "/customers/") || strings.HasPrefix(path, "/purchases/")) && strings.HasSuffix(path, "/payments"))
	if !eligible || body == nil {
		return body
	}
	b, e := json.Marshal(body)
	if e != nil {
		return body
	}
	var d map[string]any
	if json.Unmarshal(b, &d) != nil || d == nil {
		return body
	}
	if _, ok := d["account_id"]; !ok {
		if _, third := d["creditor_id"]; !third {
			d["account_id"] = "00000000-0000-0000-0000-000000000999"
			method, _ := d["method"].(string)
			if v, ok := d["method_code"].(string); ok {
				method = v
			}
			if v, ok := d["payment_method"].(string); ok {
				method = v
			}
			if method != "" && method != "CASH" && method != "OTHER" {
				d["account_id"] = "00000000-0000-0000-0000-000000000998"
			}
		}
	}
	return d
}

// SeedPaymentAccount prepares only a disposable integration database.
func SeedPaymentAccount(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	_, err := conn.Exec(context.Background(), `INSERT INTO app.money_accounts(id,name,bank,account_type,created_by,request_id,request_payload)
 SELECT '00000000-0000-0000-0000-000000000999','Fixture cash','Cash','CASH',id,'00000000-0000-0000-0000-000000000999','{}' FROM app.users WHERE role_code='SUPER_ADMIN' ORDER BY created_at LIMIT 1;
 INSERT INTO app.account_entries(account_id,kind,amount_mmk,sender,description,occurred_at,recorded_by)
 SELECT id,'EXTERNAL_DEPOSIT',1000000000000,'Fixture funding','Test opening funds','2000-01-01',created_by FROM app.money_accounts WHERE id='00000000-0000-0000-0000-000000000999';
 INSERT INTO app.money_accounts(id,name,bank,account_type,created_by,request_id,request_payload) SELECT '00000000-0000-0000-0000-000000000998','Fixture bank','Test bank','BANK',created_by,'00000000-0000-0000-0000-000000000998','{}' FROM app.money_accounts WHERE id='00000000-0000-0000-0000-000000000999';
 INSERT INTO app.account_entries(account_id,kind,amount_mmk,sender,description,occurred_at,recorded_by) SELECT '00000000-0000-0000-0000-000000000998','EXTERNAL_DEPOSIT',1000000000000,'Fixture funding','Opening funds','2000-01-01',created_by FROM app.money_accounts WHERE id='00000000-0000-0000-0000-000000000999';
 SELECT set_config('app.payment_account','00000000-0000-0000-0000-000000000999',false);`)
	if err != nil {
		t.Fatal(err)
	}
}
