package migrate

import (
	"context"
	"encoding/json"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"io/fs"
	"os"
	"strings"
	"testing"
	"testing/fstest"
)

func TestTransferCostLayersIntegration(t *testing.T) {
	ctx := context.Background()
	db := testutil.Database(t)
	source := os.DirFS("../../../database/migrations")
	old := fstest.MapFS{}
	names, e := fs.ReadDir(source, ".")
	if e != nil {
		t.Fatal(e)
	}
	for _, name := range names {
		if name.Name() < "000048" {
			b, e := fs.ReadFile(source, name.Name())
			if e != nil {
				t.Fatal(e)
			}
			old[name.Name()] = &fstest.MapFile{Data: b}
		}
	}
	if e := Up(ctx, db, old); e != nil {
		t.Fatal(e)
	}
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, e := db.Exec(ctx, sql, args...); e != nil {
			t.Fatal(e)
		}
	}
	scalar := func(sql string, args ...any) string {
		t.Helper()
		var v string
		if e := db.QueryRow(ctx, sql, args...).Scan(&v); e != nil {
			t.Fatal(e)
		}
		return v
	}
	fixture, e := os.ReadFile("../../../database/tests/fixture.sql")
	if e != nil {
		t.Fatal(e)
	}
	exec(string(fixture))
	const actor = "00000000-0000-0000-0000-000000000001"
	const batch = "00000000-0000-0000-0000-000000000070"
	const origin = "00000000-0000-0000-0000-000000000012"
	const product = "00000000-0000-0000-0000-000000000020"
	exec(`UPDATE app.batches SET finalized_at=now();UPDATE app.goods_receiving SET status='POSTED',posted_at=now();UPDATE app.sales SET status='POSTED',posted_at=now();`)
	exec(`INSERT INTO app.product_units(product_id,unit_code,units_per_pack,retail_price_mmk,wholesale_price_mmk) VALUES($1,'BOTTLE',1,40000,40000) ON CONFLICT(product_id,unit_code) DO UPDATE SET retail_price_mmk=40000,wholesale_price_mmk=40000`, product)
	dest := scalar(`INSERT INTO app.warehouses(code,name) VALUES('FIFO','FIFO destination') RETURNING id::text`)
	next := func() string { return scalar("SELECT gen_random_uuid()::text") }
	call := func(name string, d map[string]any) string {
		t.Helper()
		payload, _ := json.Marshal(d)
		return scalar("SELECT app."+name+"($1::jsonb,$2::uuid)::text", payload, actor)
	}
	transfer := func(fee string) string {
		t.Helper()
		version := scalar("SELECT version::text FROM app.inventory WHERE warehouse_id=$1 AND batch_id=$2", origin, batch)
		shipment := call("dispatch_transfer", map[string]any{"request_id": next(), "from_warehouse_id": origin, "to_warehouse_id": dest, "items": []map[string]any{{"batch_id": batch, "version": version, "quantity": "2"}}})
		exec(`INSERT INTO app.transportation_stages(shipment_id,stage_number,start_location,destination,provider_name,transportation_fee_mmk) VALUES($1,1,'A','B','Cargo',$2::numeric)`, shipment, fee)
		item := scalar("SELECT i.id::text FROM app.stock_transfer_items i JOIN app.stock_transfers t ON t.id=i.transfer_id WHERE t.shipment_id=$1", shipment)
		version = scalar("SELECT version::text FROM app.shipments WHERE id=$1", shipment)
		call("receive_transfer", map[string]any{"shipment_id": shipment, "version": version, "items": []map[string]any{{"id": item, "received_quantity": "2", "damaged_quantity": "0", "notes": ""}}})
		return item
	}
	legacyItem := transfer("100")
	legacyBatch := scalar("SELECT id::text FROM app.batches WHERE transfer_item_id=$1", legacyItem)
	// Migration must move existing reservations with the physical stock.
	call("adjust_inventory", map[string]any{"request_id": next(), "warehouse_id": dest, "batch_id": legacyBatch, "version": "1", "bucket": "RESERVED", "quantity_delta": "1", "reason": "Reserve fixture"})
	if e := Up(ctx, db, source); e != nil {
		t.Fatal(e)
	}
	if scalar("SELECT sellable_quantity::text||'/'||reserved_quantity::text FROM app.inventory WHERE warehouse_id=$1 AND batch_id=$2", dest, batch) != "2.000000/1.000000" {
		t.Fatal("legacy quantities not consolidated")
	}
	if scalar("SELECT count(*)::text FROM app.inventory_cost_layers l JOIN app.batches b ON b.id=$1 WHERE l.warehouse_id=$2 AND l.batch_id=$3 AND l.fifo_received_at=b.received_at", legacyBatch, dest, batch) != "1" {
		t.Fatal("legacy FIFO arrival date lost")
	}
	if scalar("SELECT actual_unit_cost_mmk::text FROM app.batches WHERE id=$1", legacyBatch) != "30050.00000000" {
		t.Fatal("legacy costing changed")
	}
	call("adjust_inventory", map[string]any{"request_id": next(), "warehouse_id": dest, "batch_id": batch, "version": scalar("SELECT version::text FROM app.inventory WHERE warehouse_id=$1 AND batch_id=$2", dest, batch), "bucket": "RESERVED", "quantity_delta": "-1", "reason": "Release fixture"})
	exec(`INSERT INTO app.product_units(product_id,unit_code,units_per_pack,retail_price_mmk,wholesale_price_mmk) VALUES($1,'PACK',2,80000,80000)`, product)
	count := scalar("SELECT count(*)::text FROM app.batches")
	transfer("200")
	if scalar("SELECT count(*)::text FROM app.batches") != count {
		t.Fatal("transfer created a batch")
	}
	if scalar("SELECT count(*)::text FROM app.inventory WHERE warehouse_id=$1 AND sellable_quantity>0", dest) != "1" {
		t.Fatal("split inventory")
	}
	if scalar("SELECT count(*)::text FROM app.inventory_cost_layers WHERE warehouse_id=$1 AND sellable_quantity>0", dest) != "2" {
		t.Fatal("lost separate cost records")
	}
	d := map[string]any{"request_id": next(), "warehouse_id": dest, "pricing_mode": "RETAIL", "tender_mmk": "120000", "payment_method": "CASH", "account_id": "00000000-0000-0000-0000-000000000999", "reason": "FIFO regression", "items": []map[string]any{{"product_id": product, "unit_code": "BOTTLE", "units_per_pack": "1", "quantity": "1", "unit_price_mmk": "40000", "discount_mmk": "0"}, {"product_id": product, "unit_code": "PACK", "units_per_pack": "2", "quantity": "1", "unit_price_mmk": "80000", "discount_mmk": "0"}}}
	payload, _ := json.Marshal(d)
	var quote map[string]any
	if e := json.Unmarshal([]byte(scalar("SELECT app.pos_sale($1::jsonb,$2::uuid,true,true,true)::text", payload, actor)), &quote); e != nil {
		t.Fatal(e)
	}
	if quote["cost_mmk"] != "90200.0000" {
		t.Fatal("wrong FIFO quote", quote)
	}
	d["quote_hash"] = quote["quote_hash"]
	payload, _ = json.Marshal(d)
	sale := scalar("SELECT app.pos_sale($1::jsonb,$2::uuid,true,true,false)::text", payload, actor)
	if !strings.Contains(sale, "invoice_number") {
		t.Fatal(sale)
	}
	if scalar("SELECT app.inventory_cost($1,$2)::text", batch, dest) != "30100.00000000" {
		t.Fatal("did not consume oldest cost first")
	}
	if scalar("SELECT count(*)::text FROM app.sale_item_batches WHERE cost_layer_id IS NOT NULL") != "3" {
		t.Fatal("sale collapsed distinct costs")
	}

	var posted map[string]string
	if e := json.Unmarshal([]byte(sale), &posted); e != nil {
		t.Fatal(e)
	}
	allocation := scalar("SELECT b.id::text FROM app.sale_item_batches b JOIN app.sale_items i ON i.id=b.sale_item_id WHERE i.sale_id=$1 AND b.unit_cost_mmk=30050 ORDER BY b.id LIMIT 1", posted["id"])
	call("sales_return_post", map[string]any{"request_id": next(), "sale_id": posted["id"], "resolution": "REFUND", "refund_mmk": "40000", "method": "CASH", "account_id": "00000000-0000-0000-0000-000000000999", "reason": "Return FIFO cost", "items": []map[string]any{{"sale_item_batch_id": allocation, "quantity": "1", "disposition": "DAMAGED"}}})
	if scalar("SELECT app.inventory_cost($1,$2,'DAMAGED')::text", batch, dest) != "30050.00000000" {
		t.Fatal("return lost original sold cost")
	}
	call("stock_issue", map[string]any{"request_id": next(), "batch_id": batch, "warehouse_id": dest, "version": scalar("SELECT version::text FROM app.inventory WHERE batch_id=$1 AND warehouse_id=$2", batch, dest), "kind": "MISSING", "bucket": "SELLABLE", "quantity": "1", "reason": "Missing FIFO cost"})
	if scalar("SELECT estimated_loss_mmk::text FROM app.missing_products WHERE batch_id=$1 AND warehouse_id=$2", batch, dest) != "30100.0000" {
		t.Fatal("loss used original batch price instead of FIFO cost")
	}
	if _, e := db.Exec(ctx, "UPDATE app.inventory_cost_layers SET unit_cost_mmk=1 WHERE batch_id=$1", batch); e == nil {
		t.Fatal("cost history was mutable")
	}
	if e := Up(ctx, db, source); e != nil {
		t.Fatal(e)
	}
}
