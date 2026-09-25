package receiving_test

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/receiving"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/shipments"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"io"
	"log/slog"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
)

func TestReceivingIntegration(t *testing.T) {
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
	shipments.New(pool).Register(r, a)
	receiving.New(pool).Register(r, a)
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

	_, err = conn.Exec(ctx, `INSERT INTO app.suppliers(id,code,name) VALUES('00000000-0000-0000-0000-000000000001','SUP','Supplier');INSERT INTO app.products(id,sku,name,base_unit_code) VALUES('00000000-0000-0000-0000-000000000002','TEA','Tea','BOTTLE');INSERT INTO app.purchases(id,purchase_number,supplier_id,purchased_at,currency_code,mmk_per_unit,created_by) SELECT '00000000-0000-0000-0000-000000000003','PO-1','00000000-0000-0000-0000-000000000001',now(),'MMK',1,id FROM app.users WHERE username='owner';INSERT INTO app.purchase_items(id,purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original) VALUES('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000003',1,'00000000-0000-0000-0000-000000000002','BOTTLE',100,1,100);UPDATE app.purchases SET status='POSTED',posted_at=now()`)
	if err != nil {
		t.Fatal(err)
	}
	warehouse := call("POST", "/warehouses", map[string]any{"code": "MAIN", "name": "Pwint Thit Warehouse"}, owner, 201)

	ship := call("POST", "/shipments", map[string]any{"request_id": "10000000-0000-0000-0000-000000000001", "shipment_number": "REC-SHIP", "start_location": "India", "destination_warehouse_id": warehouse["id"], "items": []map[string]any{{"purchase_item_id": "00000000-0000-0000-0000-000000000004", "expected_quantity": "60"}}}, owner, 201)
	sid := ship["id"].(string)
	_, err = conn.Exec(ctx, `INSERT INTO app.product_units(product_id,unit_code,units_per_pack) VALUES('00000000-0000-0000-0000-000000000002','CARTON',12);UPDATE app.shipment_items SET purchase_cost_mmk=6000,allocated_transport_mmk=1000,allocated_expense_mmk=500,costing_sellable_quantity=50 WHERE shipment_id=$1;INSERT INTO app.shipment_costings(shipment_id,document,finalized_by) SELECT $1,'{}',id FROM app.users WHERE username='owner';UPDATE app.shipments SET status='ARRIVED',arrived_at='2026-09-01T00:00:00Z',costs_finalized_at=now(),costs_finalized_by=(SELECT id FROM app.users WHERE username='owner') WHERE id=$1`, pgx.QueryExecModeSimpleProtocol, sid)
	if err != nil {
		t.Fatal(err)
	}
	info := call("GET", "/receiving/shipments/"+sid, nil, owner, 200)
	item := info["items"].([]any)[0].(map[string]any)
	line := map[string]any{"shipment_item_id": item["id"], "carton_size": "12", "received_cartons": "4", "received_units": "7", "damaged_quantity": "5", "batch_number": "B-RECEIVED", "notes": "5 missing and 5 damaged in transit"}
	body := map[string]any{"request_id": "20000000-0000-0000-0000-000000000001", "shipment_id": sid, "version": info["version"], "receipt_number": "REC-1", "received_at": "2026-09-02T00:00:00Z", "items": []map[string]any{line}}
	call("POST", "/receiving", body, "", 401)
	call("POST", "/receiving", body, staff, 403)
	line["received_units"] = "8"
	call("POST", "/receiving", body, owner, 409)
	if got := call("GET", "/inventory", nil, owner, 200); got["total"] != float64(0) {
		t.Fatal("failed receipt changed stock")
	}
	line["received_units"] = "7"
	line["carton_size"] = "10"
	call("POST", "/receiving", body, owner, 409)
	line["carton_size"] = "12"
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for n := 0; n < 2; n++ {
		wg.Add(1)
		go func() { defer wg.Done(); codes <- raw("POST", "/receiving", body, owner).Code }()
	}
	wg.Wait()
	close(codes)
	for code := range codes {
		if code != 201 {
			t.Fatal("duplicate receipt request", code)
		}
	}
	receipt := call("POST", "/receiving", body, owner, 201)
	details := call("GET", "/receiving/"+receipt["id"].(string), nil, owner, 200)
	ri := details["items"].([]any)[0].(map[string]any)
	if ri["expected_quantity"] != "60.000000" || ri["received_quantity"] != "55.000000" || ri["missing_quantity"] != "5.000000" || ri["damaged_quantity"] != "5.000000" || ri["sellable_quantity"] != "50.000000" {
		t.Fatal("receiving quantities", ri)
	}
	inv := call("GET", "/inventory", nil, owner, 200)["stock"].([]any)[0].(map[string]any)
	if inv["available_quantity"] != "50.000000" || inv["damaged_quantity"] != "5.000000" || inv["available_cartons"] != "4" || inv["available_units"] != "2.000000" || inv["unit_cost_mmk"] != "150.00000000" {
		t.Fatal("stock and landed cost", inv)
	}
	batchID := inv["batch_id"].(string)
	adj := map[string]any{"request_id": "30000000-0000-0000-0000-000000000001", "warehouse_id": warehouse["id"], "batch_id": batchID, "version": inv["version"], "bucket": "RESERVED", "quantity_delta": "12", "reason": "Reserve one carton for customer pickup"}
	call("POST", "/inventory/adjustments", adj, staff, 403)
	call("POST", "/inventory/adjustments", adj, owner, 201)
	call("POST", "/inventory/adjustments", adj, owner, 201)
	inv = call("GET", "/inventory", nil, owner, 200)["stock"].([]any)[0].(map[string]any)
	if inv["available_quantity"] != "38.000000" || inv["reserved_quantity"] != "12.000000" {
		t.Fatal("reservation", inv)
	}
	adj["request_id"] = "30000000-0000-0000-0000-000000000002"
	adj["quantity_delta"] = "100"
	call("POST", "/inventory/adjustments", adj, owner, 409)
	adj["version"] = inv["version"]
	call("POST", "/inventory/adjustments", adj, owner, 409)
	adj["quantity_delta"] = "-12"
	call("POST", "/inventory/adjustments", adj, owner, 201)
	inv = call("GET", "/inventory", nil, owner, 200)["stock"].([]any)[0].(map[string]any)
	adj["request_id"] = "30000000-0000-0000-0000-000000000003"
	adj["version"] = inv["version"]
	adj["bucket"] = "SELLABLE"
	adj["quantity_delta"] = "-3"
	adj["reason"] = "Controlled physical count correction"
	call("POST", "/inventory/adjustments", adj, owner, 201)
	inv = call("GET", "/inventory", nil, owner, 200)["stock"].([]any)[0].(map[string]any)
	if inv["available_quantity"] != "47.000000" {
		t.Fatal("individual-unit correction", inv)
	}
	moves := call("GET", "/inventory/movements?batch_id="+batchID, nil, owner, 200)
	if moves["total"] != float64(4) {
		t.Fatal("duplicate or missing movements", moves)
	}
	for _, statement := range []string{`UPDATE app.inventory SET sellable_quantity=999`, `DELETE FROM app.inventory`, `DELETE FROM app.inventory_movements`, `UPDATE app.goods_receiving_items SET received_quantity=1`, `UPDATE app.batches SET purchase_cost_mmk=1`} {
		if _, err = conn.Exec(ctx, statement); err == nil {
			t.Fatal("uncontrolled mutation allowed", statement)
		}
	}
	var balanced bool
	err = conn.QueryRow(ctx, `SELECT i.sellable_quantity=sum(m.sellable_delta) AND i.reserved_quantity=sum(m.reserved_delta) AND i.damaged_quantity=sum(m.damaged_delta) FROM app.inventory i JOIN app.inventory_movements m USING(warehouse_id,batch_id) GROUP BY i.sellable_quantity,i.reserved_quantity,i.damaged_quantity`).Scan(&balanced)
	if err != nil || !balanced {
		t.Fatal("movement ledger does not reconcile", err)
	}
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,'inventory.view',o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner'`)
	if err != nil {
		t.Fatal(err)
	}
	hidden := call("GET", "/inventory", nil, staff, 200)["stock"].([]any)[0].(map[string]any)
	if _, ok := hidden["unit_cost_mmk"]; ok {
		t.Fatal("cost exposed")
	}
	hiddenMove := call("GET", "/inventory/movements", nil, staff, 200)["movements"].([]any)[0].(map[string]any)
	if _, ok := hiddenMove["unit_cost_mmk"]; ok {
		t.Fatal("movement cost exposed")
	}
	// Fully missing and fully damaged goods keep their finalized costs without dividing by zero.
	for n, received := range []string{"0", "20"} {
		ship := call("POST", "/shipments", map[string]any{"request_id": fmt.Sprintf("40000000-0000-0000-0000-%012d", n+1), "shipment_number": fmt.Sprintf("LOSS-%d", n), "start_location": "India", "destination_warehouse_id": warehouse["id"], "items": []map[string]any{{"purchase_item_id": "00000000-0000-0000-0000-000000000004", "expected_quantity": "20"}}}, owner, 201)
		sid := ship["id"].(string)
		_, err = conn.Exec(ctx, `UPDATE app.shipment_items SET purchase_cost_mmk=2000,allocated_transport_mmk=0,allocated_expense_mmk=0,costing_sellable_quantity=0 WHERE shipment_id=$1;INSERT INTO app.shipment_costings(shipment_id,document,finalized_by) SELECT $1,'{}',id FROM app.users WHERE username='owner';UPDATE app.shipments SET status='ARRIVED',arrived_at='2026-09-01T00:00:00Z',costs_finalized_at=now(),costs_finalized_by=(SELECT id FROM app.users WHERE username='owner') WHERE id=$1`, pgx.QueryExecModeSimpleProtocol, sid)
		if err != nil {
			t.Fatal(err)
		}
		info := call("GET", "/receiving/shipments/"+sid, nil, owner, 200)
		item := info["items"].([]any)[0].(map[string]any)
		receipt := call("POST", "/receiving", map[string]any{"request_id": fmt.Sprintf("50000000-0000-0000-0000-%012d", n+1), "shipment_id": sid, "version": info["version"], "receipt_number": fmt.Sprintf("LOSS-REC-%d", n), "received_at": "2026-09-02T00:00:00Z", "items": []map[string]any{{"shipment_item_id": item["id"], "carton_size": "12", "received_cartons": "0", "received_units": received, "damaged_quantity": received, "batch_number": fmt.Sprintf("LOSS-B-%d", n), "notes": "Entire shipment lost or damaged"}}}, owner, 201)
		detail := call("GET", "/receiving/"+receipt["id"].(string), nil, owner, 200)
		bid := detail["items"].([]any)[0].(map[string]any)["batch_id"].(string)
		var preserved bool
		if err = conn.QueryRow(ctx, `SELECT actual_unit_cost_mmk IS NULL AND purchase_cost_mmk=2000 AND sellable_quantity=0 FROM app.batches WHERE id=$1`, bid).Scan(&preserved); err != nil || !preserved {
			t.Fatal("zero sellable batch cost", err)
		}
		moves := call("GET", "/inventory/movements?batch_id="+bid, nil, owner, 200)
		if moves["total"] != float64(n) {
			t.Fatal("zero-sellable movements", moves)
		}
	}

	call("GET", "/batches", nil, "", 401)
	batches := call("GET", "/batches", nil, owner, 200)
	if batches["total"] != float64(3) {
		t.Fatal("batch history must include wholly lost goods", batches)
	}
	for _, row := range batches["batches"].([]any) {
		b := row.(map[string]any)
		if b["total_cost_mmk"] == nil || b["received_at"] == nil {
			t.Fatal("batch historical metadata missing", b)
		}
	}
	hiddenBatch := call("GET", "/batches", nil, staff, 200)["batches"].([]any)[0].(map[string]any)
	if _, ok := hiddenBatch["total_cost_mmk"]; ok {
		t.Fatal("batch cost exposed")
	}
	call("GET", "/batches?expiry=invalid", nil, owner, 400)
	var statuses string
	err = conn.QueryRow(ctx, `SELECT string_agg(app.expiry_status(d,'2026-01-01'::date),',') FROM unnest(ARRAY[NULL::date,'2025-12-31','2026-01-01','2026-01-31','2026-02-01','2026-03-02','2026-03-03']::date[]) d`).Scan(&statuses)
	if err != nil || statuses != "NO_EXPIRY,EXPIRED,EXPIRING_30,EXPIRING_30,EXPIRING_60,EXPIRING_60,CURRENT" {
		t.Fatal("expiry boundaries", statuses, err)
	}

}
