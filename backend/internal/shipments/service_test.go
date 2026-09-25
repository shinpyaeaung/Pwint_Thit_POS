package shipments_test

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

func TestShipmentIntegration(t *testing.T) {
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
	create := func(n int, qty string) map[string]any {
		return map[string]any{"request_id": fmt.Sprintf("10000000-0000-0000-0000-%012d", n), "shipment_number": fmt.Sprintf("SH-%d", n), "start_location": "India", "destination_warehouse_id": warehouse["id"], "items": []map[string]any{{"purchase_item_id": "00000000-0000-0000-0000-000000000004", "expected_quantity": qty}}}
	}
	call("GET", "/shipments", nil, "", 401)
	call("POST", "/shipments", create(1, "60"), staff, 403)
	ship := call("POST", "/shipments", create(1, "60"), owner, 201)
	id := ship["id"].(string)
	call("POST", "/shipments", create(1, "60"), owner, 409)
	call("POST", "/shipments", create(2, "50"), owner, 409)
	if got := call("GET", "/shipments", nil, owner, 200); got["total"] != float64(1) {
		t.Fatal("partial shipment persisted")
	}
	version := func() any { return call("GET", "/shipments/"+id, nil, owner, 200)["version"] }
	stage := func(n int) map[string]any {
		return map[string]any{"request_id": fmt.Sprintf("20000000-0000-0000-0000-%012d", n), "version": version(), "start_location": "India", "destination": fmt.Sprintf("City %d", n), "provider_name": "Road carrier", "transportation_fee_mmk": "30000.1234", "loading_fee_mmk": "100", "unloading_fee_mmk": "200", "other_fee_mmk": "50", "departed_at": "2026-09-01T00:00:00Z", "arrived_at": "2026-09-02T00:00:00Z"}
	}
	first := stage(1)
	call("POST", "/shipments/"+id+"/stages", first, owner, 204)
	call("POST", "/shipments/"+id+"/stages", first, owner, 409)
	for n := 2; n <= 25; n++ {
		call("POST", "/shipments/"+id+"/stages", stage(n), owner, 204)
	}
	page := call("GET", "/shipments/"+id+"/stages?page=2&page_size=20", nil, owner, 200)
	if page["total"] != float64(25) || len(page["stages"].([]any)) != 5 {
		t.Fatal("stage cap/pagination", page)
	}
	detail := call("GET", "/shipments/"+id, nil, owner, 200)
	if detail["transport_total_mmk"] != "758753.0850" {
		t.Fatal("exact transport sum", detail)
	}
	stages := call("GET", "/shipments/"+id+"/stages", nil, owner, 200)
	child := stages["stages"].([]any)[0].(map[string]any)["id"].(string)
	edit := stage(99)
	delete(edit, "request_id")
	edit["transportation_fee_mmk"] = "30001.1234"
	call("PUT", "/shipments/"+id+"/stages/"+child, edit, owner, 204)
	bad := stage(26)
	bad["transportation_fee_mmk"] = "NaN"
	call("POST", "/shipments/"+id+"/stages", bad, owner, 400)
	bad = stage(26)
	bad["arrived_at"] = "2026-08-01T00:00:00Z"
	call("POST", "/shipments/"+id+"/stages", bad, owner, 400)
	expense := map[string]any{"version": version(), "request_id": "30000000-0000-0000-0000-000000000001", "category": "Customs", "description": "Border customs", "currency_code": "INR", "amount_original": "100.1234", "mmk_per_unit": "25", "incurred_at": "2026-09-02T00:00:00Z"}
	call("POST", "/shipments/"+id+"/expenses", expense, owner, 204)
	expenses := call("GET", "/shipments/"+id+"/expenses", nil, owner, 200)
	ex := expenses["expenses"].([]any)[0].(map[string]any)
	if ex["amount_mmk"] != "2503.0850" {
		t.Fatal("expense conversion", ex)
	}
	exID := ex["id"].(string)
	call("POST", "/shipments/"+id+"/expenses/"+exID+"/void", map[string]any{"version": version(), "reason": "Duplicate receipt"}, owner, 204)
	if got := call("GET", "/shipments/"+id, nil, owner, 200); got["expense_total_mmk"] != "0" {
		t.Fatal("void affects total", got)
	}
	// Payment status comes from posted allocations; allocated cost records cannot be edited.
	_, err = conn.Exec(ctx, `WITH payment AS(INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,paid_at,recorded_by) SELECT 'TRANSPORT','OUT','CASH','MMK',100,1,now(),id FROM app.users WHERE username='owner' RETURNING id) INSERT INTO app.payment_allocations(payment_id,transportation_stage_id,settlement_mmk,applied_mmk,applied_original) SELECT id,$1,100,100,100 FROM payment`, child)
	if err != nil {
		t.Fatal(err)
	}
	_, err = conn.Exec(ctx, `UPDATE app.payments SET status='POSTED',posted_at=now()`)
	if err != nil {
		t.Fatal(err)
	}
	stages = call("GET", "/shipments/"+id+"/stages", nil, owner, 200)
	if stages["stages"].([]any)[0].(map[string]any)["payment_status"] != "PARTIALLY_PAID" {
		t.Fatal("payment status")
	}
	edit["version"] = version()
	call("PUT", "/shipments/"+id+"/stages/"+child, edit, owner, 409)
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,'shipments.view',o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner'`)
	if err != nil {
		t.Fatal(err)
	}
	hidden := call("GET", "/shipments/"+id, nil, staff, 200)
	if _, ok := hidden["transport_total_mmk"]; ok {
		t.Fatal("cost exposed")
	}
	hidden = call("GET", "/shipments/"+id+"/stages", nil, staff, 200)
	if _, ok := hidden["stages"].([]any)[0].(map[string]any)["total_mmk"]; ok {
		t.Fatal("stage cost exposed")
	}
	call("POST", "/shipments/"+id+"/stages", stage(26), staff, 403)
	call("PUT", "/shipments/"+id+"/status", map[string]any{"version": version(), "status": "RECEIVED"}, owner, 409)
	call("PUT", "/shipments/"+id+"/status", map[string]any{"version": version(), "status": "IN_TRANSIT", "shipped_at": "2026-09-01T00:00:00Z"}, owner, 204)
	call("PUT", "/shipments/"+id+"/status", map[string]any{"version": version(), "status": "ARRIVED", "arrived_at": "2026-08-01T00:00:00Z"}, owner, 400)
	call("PUT", "/shipments/"+id+"/status", map[string]any{"version": version(), "status": "ARRIVED", "arrived_at": "2026-09-03T00:00:00Z"}, owner, 204)
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for _, n := range []int{3, 4} {
		wg.Add(1)
		go func(n int) { defer wg.Done(); codes <- raw("POST", "/shipments", create(n, "30"), owner).Code }(n)
	}
	wg.Wait()
	close(codes)
	counts := map[int]int{}
	for code := range codes {
		counts[code]++
	}
	if counts[201] != 1 || counts[409] != 1 {
		t.Fatal("over-shipment race", counts)
	}

	// Cancellation releases allocation, but keeps a closed, immutable history.
	cancelled := call("POST", "/shipments", create(5, "10"), owner, 201)
	cancelID := cancelled["id"].(string)
	call("PUT", "/shipments/"+cancelID+"/status", map[string]any{"version": cancelled["version"], "status": "CANCELLED"}, owner, 204)
	closed := call("GET", "/shipments/"+cancelID, nil, owner, 200)
	blocked := stage(27)
	blocked["version"] = closed["version"]
	call("POST", "/shipments/"+cancelID+"/stages", blocked, owner, 409)
	replacement := call("POST", "/shipments", create(6, "10"), owner, 201)
	// Finalized costs cannot be changed even by Super Admin.
	_, err = conn.Exec(ctx, `UPDATE app.shipments SET costs_finalized_at=now(),costs_finalized_by=(SELECT id FROM app.users WHERE username='owner') WHERE id=$1`, replacement["id"])
	if err != nil {
		t.Fatal(err)
	}
	blocked["version"] = replacement["version"]
	call("POST", "/shipments/"+replacement["id"].(string)+"/stages", blocked, owner, 409)

	// Landed cost is protected, previewed, finalized atomically, and never falls back to purchase price.
	costPath := "/shipments/" + id + "/landed-cost"
	call("GET", costPath, nil, staff, 403)
	source := call("GET", costPath, nil, owner, 200)["source"].(map[string]any)
	costItem := source["items"].([]any)[0].(map[string]any)["id"]
	costIn := map[string]any{"version": version(), "method": "QUANTITY", "notes": "Confirmed 50 sellable units after transit", "items": []map[string]any{{"id": costItem, "sellable_quantity": "50"}}}
	cost := call("POST", costPath+"/preview", costIn, owner, 200)
	if cost["purchase_mmk"] != "6000.0000" || cost["landed_mmk"] != "764754.0850" {
		t.Fatal("landed formula", cost)
	}
	item := cost["items"].([]any)[0].(map[string]any)
	if item["actual_unit_cost_mmk"] != "15295.08170000" {
		t.Fatal("actual unit cost", item)
	}
	costIn["preview_token"] = "stale"
	call("POST", costPath+"/finalize", costIn, owner, 409)
	if snapshot := call("GET", costPath, nil, owner, 200)["snapshot"]; snapshot != nil {
		t.Fatal("failed finalization wrote snapshot")
	}
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,'finance.view_landed_cost',o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner'`)
	if err != nil {
		t.Fatal(err)
	}
	call("POST", costPath+"/preview", costIn, staff, 200)
	costIn["preview_token"] = cost["preview_token"]
	call("POST", costPath+"/finalize", costIn, staff, 403)
	// Two simultaneous finalizations must produce one snapshot and one audit.
	finalCodes := make(chan int, 2)
	for n := 0; n < 2; n++ {
		wg.Add(1)
		go func() { defer wg.Done(); finalCodes <- raw("POST", costPath+"/finalize", costIn, owner).Code }()
	}
	wg.Wait()
	close(finalCodes)
	finalCounts := map[int]int{}
	for code := range finalCodes {
		finalCounts[code]++
	}
	if finalCounts[201] != 1 || finalCounts[409] != 1 {
		t.Fatal("concurrent finalization", finalCounts)
	}
	saved := call("GET", costPath, nil, owner, 200)["snapshot"].(map[string]any)
	if saved["finalized"] != true || saved["landed_mmk"] != cost["landed_mmk"] {
		t.Fatal("snapshot mismatch", saved)
	}
	call("POST", costPath+"/finalize", costIn, owner, 409)
	call("POST", "/shipments/"+id+"/stages", stage(28), owner, 409)
	var unit string
	if err = conn.QueryRow(ctx, `SELECT actual_unit_cost_mmk::text FROM app.shipment_items WHERE id=$1`, costItem).Scan(&unit); err != nil || unit != "15295.08170000" {
		t.Fatal("persisted exact unit cost", unit, err)
	}
	for _, statement := range []string{`UPDATE app.shipment_costings SET document='{}'`, `DELETE FROM app.shipment_costings`, `UPDATE app.shipment_items SET purchase_cost_mmk=1 WHERE purchase_cost_mmk IS NOT NULL`} {
		if _, err = conn.Exec(ctx, statement); err == nil {
			t.Fatal("finalized costs mutable", statement)
		}
	}
	var finalizedAudits int
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.audit_logs WHERE action='costs.finalize'`).Scan(&finalizedAudits); err != nil || finalizedAudits != 1 {
		t.Fatal("finalization audit", finalizedAudits, err)
	}

	// Historical foreign conversion reconciles each line to the posted purchase snapshot.
	_, err = conn.Exec(ctx, `INSERT INTO app.purchases(id,purchase_number,supplier_id,purchased_at,currency_code,mmk_per_unit,created_by) SELECT '40000000-0000-0000-0000-000000000001','ROUNDING-INR','00000000-0000-0000-0000-000000000001',now(),'INR',1.5,id FROM app.users WHERE username='owner';
 INSERT INTO app.purchase_items(purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original) SELECT '40000000-0000-0000-0000-000000000001',n,'00000000-0000-0000-0000-000000000002','BOTTLE',1,1,0.0001 FROM generate_series(1,3) n;
 UPDATE app.purchases SET status='POSTED',posted_at=now() WHERE purchase_number='ROUNDING-INR'`)
	if err != nil {
		t.Fatal(err)
	}
	var lines, total string
	err = conn.QueryRow(ctx, `SELECT sum(l.total_mmk)::text,max(a.amount_mmk)::text FROM app.purchase_line_costs l JOIN app.purchase_amounts a ON a.purchase_id=l.purchase_id WHERE l.purchase_id='40000000-0000-0000-0000-000000000001'`).Scan(&lines, &total)
	if err != nil || lines != "0.0005" || lines != total {
		t.Fatal("historical line conversion lost rounding", lines, total, err)
	}

	// Split shipments share a rounding budget. Another finalization invalidates a preview even when this shipment version is unchanged.
	_, err = conn.Exec(ctx, `INSERT INTO app.purchases(id,purchase_number,supplier_id,purchased_at,currency_code,mmk_per_unit,created_by) SELECT '50000000-0000-0000-0000-000000000001','SPLIT-COST','00000000-0000-0000-0000-000000000001',now(),'MMK',1,id FROM app.users WHERE username='owner';
 INSERT INTO app.purchase_items(id,purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original) VALUES('50000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001',1,'00000000-0000-0000-0000-000000000002','BOTTLE',3,1,0.000033);
 UPDATE app.purchases SET status='POSTED',posted_at=now() WHERE purchase_number='SPLIT-COST'`)
	if err != nil {
		t.Fatal(err)
	}
	paths := []string{}
	bodies := []map[string]any{}
	for n := 1; n <= 3; n++ {
		sid := fmt.Sprintf("60000000-0000-0000-0000-%012d", n)
		_, err = conn.Exec(ctx, `INSERT INTO app.shipments(id,shipment_number,start_location,destination_warehouse_id,status,created_by) SELECT $1,$2,'India',$3,'ARRIVED',id FROM app.users WHERE username='owner'`, sid, fmt.Sprintf("SPLIT-%d", n), warehouse["id"])
		if err != nil {
			t.Fatal(err)
		}
		_, err = conn.Exec(ctx, `INSERT INTO app.shipment_items(shipment_id,purchase_item_id,product_id,expected_quantity) VALUES($1,'50000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',1)`, sid)
		if err != nil {
			t.Fatal(err)
		}
		path := "/shipments/" + sid + "/landed-cost"
		src := call("GET", path, nil, owner, 200)["source"].(map[string]any)
		body := map[string]any{"version": "1", "method": "QUANTITY", "notes": "Confirmed split quantity", "items": []map[string]any{{"id": src["items"].([]any)[0].(map[string]any)["id"], "sellable_quantity": "1"}}}
		body["preview_token"] = call("POST", path+"/preview", body, owner, 200)["preview_token"]
		paths = append(paths, path)
		bodies = append(bodies, body)
	}
	call("POST", paths[0]+"/finalize", bodies[0], owner, 201)
	call("POST", paths[1]+"/finalize", bodies[1], owner, 409)
	for n := 1; n < 3; n++ {
		bodies[n]["preview_token"] = call("POST", paths[n]+"/preview", bodies[n], owner, 200)["preview_token"]
		call("POST", paths[n]+"/finalize", bodies[n], owner, 201)
	}
	var splitTotal string
	if err = conn.QueryRow(ctx, `SELECT sum(purchase_cost_mmk)::text FROM app.shipment_items WHERE purchase_item_id='50000000-0000-0000-0000-000000000002'`).Scan(&splitTotal); err != nil || splitTotal != "0.0001" {
		t.Fatal("split costs do not reconcile", splitTotal, err)
	}
	var audits int
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.audit_logs WHERE entity_type='transportation_stages'`).Scan(&audits); err != nil || audits != 26 {
		t.Fatal("audit", audits, err)
	}
}
