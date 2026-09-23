package authn_test

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"strconv"
	"syscall"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/password"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/products"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/suppliers"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
)

func TestBrowserIntegration(t *testing.T) {
	if os.Getenv("RUN_BROWSER_TESTS") != "1" {
		t.Skip("run make test-e2e for isolated browser integration")
	}
	gin.SetMode(gin.TestMode)
	conn := testutil.Database(t)
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	if err := migrate.Up(ctx, conn, os.DirFS("../../../database/migrations")); err != nil {
		t.Fatal(err)
	}
	const secret = "Browser-only test password 321!"
	hash, err := password.Hash(secret)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = conn.Exec(ctx, `INSERT INTO app.users(username,display_name,password_hash,role_code) VALUES('browser-owner','Test Owner',$1,'SUPER_ADMIN'),('browser-staff','Test Staff',$1,'STAFF_ADMIN')`, hash); err != nil {
		t.Fatal(err)
	}
	// Purchase creation belongs to a later module. Seed history only in this disposable browser database.
	if _, err = conn.Exec(ctx, `
 WITH supplier AS (INSERT INTO app.suppliers(code,name,country_code,payment_terms) VALUES('E2E-HISTORY','History Supply','IN','Net 30 days') RETURNING id),
 product AS (INSERT INTO app.products(sku,name,base_unit_code) VALUES('E2E-HISTORY','History product','PIECE') RETURNING id),
 purchases AS (INSERT INTO app.purchases(purchase_number,supplier_id,purchased_at,currency_code,mmk_per_unit,created_by)
 SELECT 'E2E-PO-'||n,supplier.id,now()-n*interval '1 day','MMK',1,u.id FROM supplier CROSS JOIN generate_series(1,11) n CROSS JOIN app.users u WHERE u.username='browser-owner' RETURNING id)
 INSERT INTO app.purchase_items(purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original)
 SELECT purchases.id,1,product.id,'PIECE',3,1,123456789.123456 FROM purchases CROSS JOIN product`); err != nil {
		t.Fatal(err)
	}
	poolConfig, err := pgxpool.ParseConfig(conn.Config().ConnString())
	if err != nil {
		t.Fatal(err)
	}
	poolConfig.ConnConfig.Database = conn.Config().Database
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	origin := fmt.Sprintf("http://127.0.0.1:%d", port)
	q := database.New(pool)
	router := httpapi.New(q, slog.New(slog.NewJSONHandler(io.Discard, nil)), authz.New(q), authn.New(pool, authn.Options{AllowedOrigins: []string{origin}}))
	products.New(pool).Register(router, authz.New(q))
	suppliers.New(pool).Register(router, authz.New(q))
	server := httptest.NewServer(router)
	defer server.Close()
	frontend := exec.Command("pnpm", "--dir", "../../../frontend", "exec", "vite", "--host", "127.0.0.1", "--port", strconv.Itoa(port), "--strictPort")
	frontend.Env = append(os.Environ(), "API_PROXY_TARGET="+server.URL)
	frontend.Stdout = os.Stdout
	frontend.Stderr = os.Stderr
	frontend.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err = frontend.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = syscall.Kill(-frontend.Process.Pid, syscall.SIGTERM); _ = frontend.Wait() }()
	ready := false
	client := http.Client{Timeout: time.Second}
	for deadline := time.Now().Add(20 * time.Second); time.Now().Before(deadline); {
		response, e := client.Get(origin)
		if e == nil {
			response.Body.Close()
			ready = response.StatusCode == 200
			if ready {
				break
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	if !ready {
		t.Fatal("test frontend did not start")
	}
	tests := exec.CommandContext(ctx, "pnpm", "--dir", "../../../frontend", "run", "test:e2e")
	tests.Env = append(os.Environ(), "E2E_BASE_URL="+origin, "E2E_USERNAME=browser-owner", "E2E_STAFF_USERNAME=browser-staff", "E2E_PASSWORD="+secret)
	tests.Stdout = os.Stdout
	tests.Stderr = os.Stderr
	if err = tests.Run(); err != nil {
		t.Fatal(err)
	}
}
