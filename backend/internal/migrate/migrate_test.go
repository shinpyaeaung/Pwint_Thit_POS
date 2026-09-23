package migrate

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
)

func TestSchemaIntegration(t *testing.T) {
	conn := testutil.Database(t)
	ctx := context.Background()
	source := os.DirFS("../../../database/migrations")
	if err := Up(ctx, conn, source); err != nil {
		t.Fatal(err)
	}
	if err := Up(ctx, conn, source); err != nil {
		t.Fatalf("repeat migration: %v", err)
	}
	fixture, err := os.ReadFile("../../../database/tests/fixture.sql")
	if err != nil {
		t.Fatal(err)
	}
	tests := []struct{ name, sql, code string }{
		{"third role", `INSERT INTO app.roles VALUES('MANAGER','Manager',now())`, "23514"},
		{"remove role", `DELETE FROM app.roles WHERE code='STAFF_ADMIN'`, "23514"},
		{"unknown role", `UPDATE app.users SET role_code='MANAGER'`, "23503"},
		{"negative money", `UPDATE app.purchase_items SET unit_price_original=-1`, "23514"},
		{"NaN money", `UPDATE app.purchase_items SET unit_price_original='NaN'`, "23514"},
		{"NaN quantity", `UPDATE app.inventory SET sellable_quantity='NaN'`, "23514"},
		{"zero exchange rate", `UPDATE app.purchases SET exchange_rate_id=NULL,mmk_per_unit=0`, "23514"},
		{"rate currency mismatch", `UPDATE app.purchases SET currency_code='USD'`, "23514"},
		{"historical rate", `UPDATE app.exchange_rates SET mmk_per_unit=30`, "23514"},
		{"wrong shipment product", `UPDATE app.shipment_items SET product_id='00000000-0000-0000-0000-000000000021'`, "23503"},
		{"wrong batch product", `UPDATE app.sale_item_batches SET product_id='00000000-0000-0000-0000-000000000021'`, "23503"},
		{"negative inventory", `UPDATE app.inventory SET sellable_quantity=-1`, "23514"},
		{"over reservation", `UPDATE app.inventory SET reserved_quantity=11`, "23514"},
		{"too many damaged", `UPDATE app.goods_receiving_items SET damaged_quantity=12`, "23514"},
		{"expiry before manufacture", `UPDATE app.batches SET manufactured_on='2026-02-01',expires_on='2026-01-01'`, "23514"},
		{"posted purchase frozen", `UPDATE app.purchases SET status='POSTED',posted_at=now(); UPDATE app.purchases SET mmk_per_unit=30,exchange_rate_id=NULL`, "23514"},
		{"posted purchase lines frozen", `UPDATE app.purchases SET status='POSTED',posted_at=now(); UPDATE app.purchase_items SET unit_price_original=9000`, "23514"},
		{"posted purchase cannot delete", `UPDATE app.purchases SET status='POSTED',posted_at=now(); DELETE FROM app.purchases`, "23514"},
		{"posted sale cost frozen", `UPDATE app.sales SET status='POSTED',posted_at=now(); UPDATE app.sale_item_batches SET unit_cost_mmk=1`, "23514"},
		{"finalized batch frozen", `UPDATE app.batches SET finalized_at=now(); UPDATE app.batches SET purchase_cost_mmk=1`, "23514"},
		{"finalized shipment frozen", `UPDATE app.shipments SET costs_finalized_at=now(),costs_finalized_by='00000000-0000-0000-0000-000000000001'; UPDATE app.shipment_items SET allocated_transport_mmk=1`, "23514"},
		{"audit append only", `INSERT INTO app.audit_logs(action,entity_type,reason) VALUES('test','users','fixture'); DELETE FROM app.audit_logs`, "23514"},
		{"duplicate username", `UPDATE app.users SET username='OWNER' WHERE username='staff'`, "23505"},
		{"unknown permission", `INSERT INTO app.user_permissions VALUES('00000000-0000-0000-0000-000000000002','unknown.permission','00000000-0000-0000-0000-000000000001',now())`, "23503"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tx, err := conn.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer tx.Rollback(ctx)
			if _, err = tx.Exec(ctx, string(fixture)); err != nil {
				t.Fatal(err)
			}
			_, err = tx.Exec(ctx, tt.sql)
			var pe *pgconn.PgError
			if !errors.As(err, &pe) || pe.Code != tt.code {
				t.Fatalf("expected SQLSTATE %s, got %v", tt.code, err)
			}
		})
	}
	t.Run("exact costs conversions and balances", func(t *testing.T) {
		tx, err := conn.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		exec(t, tx, string(fixture))
		for query, want := range map[string]string{
			`SELECT total_mmk::text FROM app.purchase_totals`:              "250000.0000",
			`SELECT base_quantity::text FROM app.purchase_items`:           "12.000000",
			`SELECT actual_unit_cost_mmk::text FROM app.batches`:           "30000.00000000",
			`SELECT missing_quantity::text FROM app.goods_receiving_items`: "1.000000",
			`SELECT available_quantity::text FROM app.inventory`:           "8.000000",
		} {
			var got string
			if err = tx.QueryRow(ctx, query).Scan(&got); err != nil || got != want {
				t.Fatalf("%s: %s, %v; want %s", query, got, err, want)
			}
		}
		exec(t, tx, `UPDATE app.sales SET status='POSTED',posted_at=now(); UPDATE app.purchases SET status='POSTED',posted_at=now();`)
		var debt, payable string
		if err = tx.QueryRow(ctx, `SELECT outstanding_mmk::text FROM app.customer_debts`).Scan(&debt); err != nil || debt != "80000.0000" {
			t.Fatalf("debt: %s %v", debt, err)
		}
		if err = tx.QueryRow(ctx, `SELECT outstanding_original::text FROM app.supplier_payables`).Scan(&payable); err != nil || payable != "10000.0000" {
			t.Fatalf("payable: %s %v", payable, err)
		}
		exec(t, tx, `UPDATE app.sales SET status='REVERSED';`)
		var count int
		if err = tx.QueryRow(ctx, `SELECT count(*) FROM app.customer_debts`).Scan(&count); err != nil || count != 0 {
			t.Fatal("reversed sale remains in debt")
		}
	})

	t.Run("payment allocation constraints and credit balances", func(t *testing.T) {
		tx, err := conn.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		exec(t, tx, string(fixture))
		exec(t, tx, `UPDATE app.sales SET status='POSTED',posted_at=now(); UPDATE app.purchases SET status='POSTED',posted_at=now();
   INSERT INTO app.payments(id,payment_number,direction,method,currency_code,amount_original,mmk_per_unit,customer_id,paid_at,recorded_by) VALUES
   ('00000000-0000-0000-0000-000000000090','PAY-1','IN','CASH','MMK',40000,1,'00000000-0000-0000-0000-000000000011',now(),'00000000-0000-0000-0000-000000000001');
   INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) VALUES
   ('00000000-0000-0000-0000-000000000090','00000000-0000-0000-0000-000000000080',40000,40000,40000);
   UPDATE app.payments SET status='POSTED',posted_at=now();`)
		var debt string
		if err = tx.QueryRow(ctx, `SELECT outstanding_mmk::text FROM app.customer_debts`).Scan(&debt); err != nil || debt != "40000.0000" {
			t.Fatalf("partial payment: %s %v", debt, err)
		}
		exec(t, tx, `INSERT INTO app.sales_returns(id,return_number,sale_id,return_type,returned_at,reason,created_by) VALUES
  ('00000000-0000-0000-0000-000000000092','RET-1','00000000-0000-0000-0000-000000000080','CREDIT',now(),'partial return','00000000-0000-0000-0000-000000000001');
  INSERT INTO app.sales_return_items(sales_return_id,sale_id,sale_item_id,sale_item_batch_id,product_id,quantity,refund_mmk,disposition) VALUES
  ('00000000-0000-0000-0000-000000000092','00000000-0000-0000-0000-000000000080','00000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000020',1,40000,'SELLABLE');
  UPDATE app.sales_returns SET status='POSTED',posted_at=now();`)
		if err = tx.QueryRow(ctx, `SELECT outstanding_mmk::text FROM app.customer_debts`).Scan(&debt); err != nil || debt != "0.0000" {
			t.Fatalf("return credit: %s %v", debt, err)
		}
		exec(t, tx, `INSERT INTO app.payments(id,payment_number,direction,method,currency_code,amount_original,mmk_per_unit,supplier_id,paid_at,recorded_by) VALUES
  ('00000000-0000-0000-0000-000000000093','PAY-2','OUT','BANK_TRANSFER','INR',3000,30,'00000000-0000-0000-0000-000000000010',now(),'00000000-0000-0000-0000-000000000001');
  INSERT INTO app.payment_allocations(payment_id,purchase_id,settlement_mmk,applied_mmk,applied_original) VALUES
  ('00000000-0000-0000-0000-000000000093','00000000-0000-0000-0000-000000000040',90000,75000,3000);
  UPDATE app.payments SET status='POSTED',posted_at=now() WHERE payment_number='PAY-2';`)
		if err = tx.QueryRow(ctx, `SELECT outstanding_original::text FROM app.supplier_payables`).Scan(&debt); err != nil || debt != "7000.0000" {
			t.Fatalf("foreign payment: %s %v", debt, err)
		}
		if err = tx.QueryRow(ctx, `SELECT outstanding_mmk::text FROM app.supplier_payables`).Scan(&debt); err != nil || debt != "175000.0000" {
			t.Fatalf("historical cost: %s %v", debt, err)
		}
	})
	for _, tt := range []struct{ name, sql string }{
		{"wrong payment direction", `UPDATE app.payments SET direction='OUT'; INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) SELECT id,'00000000-0000-0000-0000-000000000080',40000,40000,40000 FROM app.payments`},
		{"wrong payment customer", `UPDATE app.payments SET customer_id=NULL; INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) SELECT id,'00000000-0000-0000-0000-000000000080',40000,40000,40000 FROM app.payments`},
		{"allocation exceeds payment", `INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) SELECT id,'00000000-0000-0000-0000-000000000080',50000,50000,50000 FROM app.payments; UPDATE app.payments SET status='POSTED',posted_at=now()`},
		{"allocation rate mismatch", `INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) SELECT id,'00000000-0000-0000-0000-000000000080',40000,40000,1 FROM app.payments`},
	} {
		t.Run(tt.name, func(t *testing.T) {
			tx, err := conn.Begin(ctx)
			if err != nil {
				t.Fatal(err)
			}
			defer tx.Rollback(ctx)
			exec(t, tx, string(fixture))
			exec(t, tx, `INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,customer_id,paid_at,recorded_by) VALUES('PAY-1','IN','CASH','MMK',40000,1,'00000000-0000-0000-0000-000000000011',now(),'00000000-0000-0000-0000-000000000001')`)
			_, err = tx.Exec(ctx, tt.sql)
			var pe *pgconn.PgError
			if !errors.As(err, &pe) || pe.Code != "23514" {
				t.Fatalf("expected constraint rejection: %v", err)
			}
		})
	}

	t.Run("no floating point columns", func(t *testing.T) {
		var n int
		err := conn.QueryRow(ctx, `SELECT count(*) FROM information_schema.columns WHERE table_schema='app' AND data_type IN ('real','double precision','money')`).Scan(&n)
		if err != nil || n != 0 {
			t.Fatalf("inexact columns: %d %v", n, err)
		}
	})
	t.Run("checksum mismatch", func(t *testing.T) {
		files := fstest.MapFS{}
		entries, _ := fs.ReadDir(source, ".")
		for _, e := range entries {
			b, _ := fs.ReadFile(source, e.Name())
			files[e.Name()] = &fstest.MapFile{Data: b}
		}
		files[entries[0].Name()].Data = append(files[entries[0].Name()].Data, []byte("\n-- changed")...)
		if err := Up(ctx, conn, files); err == nil || !strings.Contains(err.Error(), "checksum mismatch") {
			t.Fatalf("expected checksum rejection: %v", err)
		}
	})
}
func exec(t *testing.T, tx pgx.Tx, sql string) {
	t.Helper()
	if _, err := tx.Exec(context.Background(), sql); err != nil {
		t.Fatal(err)
	}
}
func TestMigrationRollback(t *testing.T) {
	conn := testutil.Database(t)
	source := fstest.MapFS{"000001_test.sql": {Data: []byte("CREATE TABLE should_rollback(id int); SELECT missing_column;")}}
	if err := Up(context.Background(), conn, source); err == nil {
		t.Fatal("expected migration failure")
	}
	var exists bool
	if err := conn.QueryRow(context.Background(), `SELECT to_regclass('public.should_rollback') IS NOT NULL`).Scan(&exists); err != nil || exists {
		t.Fatalf("DDL did not roll back: %v", err)
	}
}
