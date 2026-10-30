package products_test

import (
	"bytes"
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
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/products"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"image"
	"image/png"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
)

func TestProductIntegration(t *testing.T) {
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
	products.New(pool).Register(r, a)
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
	input := func(sku, barcode string) map[string]any {
		return map[string]any{"sku": sku, "name": "Bottled Tea", "barcode": barcode, "base_unit_code": "BOTTLE", "minimum_stock": "99999999999999.123456", "is_active": true, "packaging": []map[string]any{{"unit_code": "BOTTLE", "units_per_pack": "1", "is_default_sale": true}, {"unit_code": "CARTON", "units_per_pack": "12", "is_default_purchase": true, "barcode": barcode + "-PACK"}}}
	}
	call("GET", "/products", nil, "", 401)
	call("GET", "/products", nil, staff, 403)
	call("POST", "/products", input("DENIED", "DENIED"), staff, 403)

	t.Run("image upload transaction", func(t *testing.T) {
		var picture bytes.Buffer
		if err := png.Encode(&picture, image.NewNRGBA(image.Rect(0, 0, 3, 3))); err != nil {
			t.Fatal(err)
		}
		upload := func(method, path string, body map[string]any, data []byte, token string, want int) map[string]any {
			t.Helper()
			var b bytes.Buffer
			writer := multipart.NewWriter(&b)
			product, _ := writer.CreateFormField("product")
			encoded, _ := json.Marshal(body)
			product.Write(encoded)
			file, _ := writer.CreateFormFile("image", "photo.png")
			file.Write(data)
			writer.Close()
			req := httptest.NewRequest(method, "/api/v1"+path, &b)
			req.Header.Set("Content-Type", writer.FormDataContentType())
			req.Header.Set("Origin", "http://app.test")
			req.Header.Set("X-Pwint-Thit-Request", "1")
			req.Header.Set("Authorization", "Bearer "+token)
			w := httptest.NewRecorder()
			r.ServeHTTP(w, req)
			if w.Code != want {
				t.Fatalf("upload got %d want %d: %s", w.Code, want, w.Body.String())
			}
			var result map[string]any
			json.Unmarshal(w.Body.Bytes(), &result)
			return result
		}
		body := input("IMAGE-TEST", "IMAGE-TEST")
		upload("POST", "/products", body, picture.Bytes(), staff, 403)
		upload("POST", "/products", body, []byte("fake PNG"), owner, 400)
		p := upload("POST", "/products", body, picture.Bytes(), owner, 201)
		id := p["id"].(string)
		path := "/products/" + id
		if p["image_version"] == nil {
			t.Fatal("missing image metadata")
		}
		if raw("GET", path+"/image", nil, " ").Code != 401 {
			t.Fatal("anonymous image access")
		}
		if raw("GET", path+"/image", nil, staff).Code != 403 {
			t.Fatal("unpermitted image access")
		}
		w := raw("GET", path+"/image", nil, owner)
		if w.Code != 200 || !bytes.Equal(w.Body.Bytes(), picture.Bytes()) {
			t.Fatal("image bytes not persisted")
		}
		body["version"] = p["version"]
		updated := call("PUT", path, body, owner, 200)
		if updated["image_version"] != p["image_version"] {
			t.Fatal("ordinary edit removed image")
		}
		body["remove_image"] = true
		call("PUT", path, body, owner, 409)
		body["version"] = updated["version"]
		// A failing audit must roll back both image and product edits.
		_, err := conn.Exec(ctx, `CREATE FUNCTION app.reject_image_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.entity_id='`+id+`'::uuid THEN RAISE EXCEPTION 'test audit failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER reject_image_audit BEFORE INSERT ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.reject_image_audit()`)
		if err != nil {
			t.Fatal(err)
		}
		call("PUT", path, body, owner, 503)
		if raw("GET", path+"/image", nil, owner).Code != 200 {
			t.Fatal("image removal escaped rollback")
		}
		if _, err = conn.Exec(ctx, `DROP TRIGGER reject_image_audit ON app.audit_logs; DROP FUNCTION app.reject_image_audit()`); err != nil {
			t.Fatal(err)
		}
		removed := call("PUT", path, body, owner, 200)
		if removed["image_version"] != nil || raw("GET", path+"/image", nil, owner).Code != 404 {
			t.Fatal("image removal failed")
		}
		body["remove_image"] = false
		body["version"] = removed["version"]
		upload("PUT", path, body, picture.Bytes(), owner, 200)
	})
	category := call("POST", "/catalog/categories", map[string]any{"name": "Drinks"}, owner, 201)
	call("POST", "/catalog/categories", map[string]any{"name": "drinks"}, owner, 409)
	brand := call("POST", "/catalog/brands", map[string]any{"name": "Tea Brand"}, owner, 201)
	call("POST", "/catalog/units", map[string]any{"code": "PALLET", "name": "Pallet"}, owner, 201)
	body := input("TEA-001", "000123")
	body["category_id"] = category["id"]
	body["brand_id"] = brand["id"]
	body["packaging"].([]map[string]any)[0]["retail_price_mmk"] = "12000"
	body["packaging"].([]map[string]any)[1]["wholesale_price_mmk"] = "176000"
	body["packaging"].([]map[string]any)[1]["purchase_price_mmk"] = "160000"
	p := call("POST", "/products", body, owner, 201)
	id := p["id"].(string)
	if p["minimum_stock"] != "99999999999999.123456" {
		t.Fatalf("decimal changed: %v", p)
	}
	packs := p["packaging"].([]any)
	if packs[0].(map[string]any)["retail_price_mmk"] != "12000.0000" || packs[1].(map[string]any)["wholesale_price_mmk"] != "176000.0000" || packs[1].(map[string]any)["purchase_price_mmk"] != "160000.0000" {
		t.Fatal("independent package prices", packs)
	}
	invalidPrice := input("INVALID-PRICE", "INVALID-PRICE")
	invalidPrice["packaging"].([]map[string]any)[0]["retail_price_mmk"] = "1.00001"
	call("POST", "/products", invalidPrice, owner, 400)

	if packs[1].(map[string]any)["units_per_pack"] != "12.000000" {
		t.Fatal("pack conversion lost")
	}
	call("GET", "/products/"+id, nil, owner, 200)
	list := call("GET", "/products?q=000123-PACK&page_size=1", nil, owner, 200)
	if list["total"] != float64(1) {
		t.Fatalf("barcode search: %v", list)
	}
	list = call("GET", "/products?category_id="+category["id"].(string)+"&brand_id="+brand["id"].(string), nil, owner, 200)
	if list["total"] != float64(1) {
		t.Fatal("filters")
	}
	call("GET", "/products?page=0", nil, owner, 400)
	call("GET", "/products?page_size=101", nil, owner, 400)
	call("GET", "/products/not-a-uuid", nil, owner, 400)
	call("POST", "/products", input("tea-001", "new-barcode"), owner, 409)
	call("POST", "/products", input("TEA-002", "000123-PACK"), owner, 409)
	invalid := input("BAD", "BAD")
	invalid["minimum_stock"] = "0.0000001"
	call("POST", "/products", invalid, owner, 400)
	invalid["minimum_stock"] = "NaN"
	call("POST", "/products", invalid, owner, 400)
	invalid = input("ROLLBACK", "R")
	invalid["packaging"].([]map[string]any)[1]["unit_code"] = "UNKNOWN"
	call("POST", "/products", invalid, owner, 400)
	if result := call("GET", "/products?q=ROLLBACK", nil, owner, 200); result["total"] != float64(0) {
		t.Fatal("partial product committed")
	}
	for _, bad := range []string{"0", "-1", "1e2", "1.0000001"} {
		broken := input("BAD-PACK", "BAD-PACK")
		broken["packaging"].([]map[string]any)[1]["units_per_pack"] = bad
		call("POST", "/products", broken, owner, 400)
	}
	broken := input("BAD-BASE", "BAD-BASE")
	broken["packaging"].([]map[string]any)[0]["units_per_pack"] = "2"
	call("POST", "/products", broken, owner, 400)
	broken = input("BAD-DEFAULT", "BAD-DEFAULT")
	broken["packaging"].([]map[string]any)[0]["is_default_purchase"] = true
	call("POST", "/products", broken, owner, 400)
	body["version"] = p["version"]
	body["name"] = "Updated tea"
	p = call("PUT", "/products/"+id, body, owner, 200)
	call("PUT", "/products/"+id, body, owner, 409)
	body["version"] = p["version"]
	body["is_active"] = false
	p = call("PUT", "/products/"+id, body, owner, 200)
	if v := call("GET", "/products?status=inactive", nil, owner, 200); v["total"] != float64(1) {
		t.Fatal("inactive filter")
	}
	_, err = conn.Exec(ctx, `INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT s.id,'products.view',o.id FROM app.users s CROSS JOIN app.users o WHERE s.username='staff' AND o.username='owner'`)
	if err != nil {
		t.Fatal(err)
	}
	call("GET", "/products", nil, staff, 200)
	call("GET", "/catalog", nil, staff, 200)
	call("PUT", "/products/"+id, body, staff, 403)
	call("DELETE", "/products/"+id, map[string]any{"version": p["version"]}, staff, 403)
	call("POST", "/catalog/brands", map[string]any{"name": "No"}, staff, 403)
	// Concurrent duplicate scans must never create two products, including across base/packaging namespaces.
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for _, sku := range []string{"RACE-A", "RACE-B"} {
		wg.Add(1)
		go func(sku string) { defer wg.Done(); codes <- raw("POST", "/products", input(sku, "RACE"), owner).Code }(sku)
	}
	wg.Wait()
	close(codes)
	counts := map[int]int{}
	for code := range codes {
		counts[code]++
	}
	if counts[201] != 1 || counts[409] != 1 {
		t.Fatalf("race: %v", counts)
	}
	// An existing transaction must keep its base unit and historical conversion.
	_, err = conn.Exec(ctx, `WITH supplier AS (INSERT INTO app.suppliers(code,name) VALUES('HISTORY','History supplier') RETURNING id), purchase AS (INSERT INTO app.purchases(purchase_number,supplier_id,purchased_at,currency_code,mmk_per_unit,created_by) SELECT 'HISTORY',supplier.id,now(),'MMK',1,u.id FROM supplier CROSS JOIN app.users u WHERE u.username='owner' RETURNING id) INSERT INTO app.purchase_items(purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original) SELECT id,1,$1,'CARTON',1,12,100 FROM purchase`, id)
	if err != nil {
		t.Fatal(err)
	}
	changedBase := input("TEA-001", "000123")
	changedBase["version"] = p["version"]
	changedBase["base_unit_code"] = "PIECE"
	changedBase["packaging"].([]map[string]any)[0]["unit_code"] = "PIECE"
	call("PUT", "/products/"+id, changedBase, owner, 409)
	call("PUT", "/catalog/categories/"+category["id"].(string), map[string]any{"name": "Drinks renamed", "is_active": false}, owner, 200)
	if got := call("GET", "/products/"+id, nil, owner, 200); got["category_name"] != "Drinks renamed" {
		t.Fatal("catalog update not reflected")
	}
	body["version"] = p["version"]
	call("PUT", "/products/"+id, body, owner, 400)
	call("DELETE", "/products/"+id, map[string]any{"version": p["version"]}, owner, 204)
	call("GET", "/products/"+id, nil, owner, 200)
	if v := call("GET", "/products?status=archived", nil, owner, 200); v["total"] != float64(1) {
		t.Fatal("archive not retained")
	}
	if v := call("GET", "/products?q=TEA-001", nil, owner, 200); v["total"] != float64(0) {
		t.Fatal("archive in active catalog")
	}
	call("POST", "/products", input("TEA-001", "OTHER"), owner, 409)
	call("PUT", "/products/"+id, body, owner, 409)
	var audits int
	if err = conn.QueryRow(ctx, `SELECT count(*) FROM app.audit_logs WHERE entity_type='products' AND entity_id=$1`, id).Scan(&audits); err != nil || audits != 4 {
		t.Fatalf("audits %d %v", audits, err)
	}
}
