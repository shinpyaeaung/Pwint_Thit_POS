package database_test

import (
	"context"
	"fmt"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/testutil"
	"os"
	"regexp"
	"sync"
	"testing"
)

func TestBusinessNumbersIntegration(t *testing.T) {
	conn := testutil.Database(t)
	ctx := context.Background()
	if e := migrate.Up(ctx, conn, os.DirFS("../../../database/migrations")); e != nil {
		t.Fatal(e)
	}
	cfg, e := pgxpool.ParseConfig(conn.Config().ConnString())
	if e != nil {
		t.Fatal(e)
	}
	cfg.ConnConfig.Database = conn.Config().Database
	pool, e := pgxpool.NewWithConfig(ctx, cfg)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	var wg sync.WaitGroup
	results := make(chan string, 24)
	errs := make(chan error, 24)
	for i := 0; i < 24; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var number string
			e := pool.QueryRow(ctx, "INSERT INTO app.suppliers(code,name) VALUES('','Concurrent supplier') RETURNING code").Scan(&number)
			if e != nil {
				errs <- e
			} else {
				results <- number
			}
		}()
	}
	wg.Wait()
	close(errs)
	close(results)
	for e := range errs {
		t.Fatal(e)
	}
	seen := map[string]bool{}
	pattern := regexp.MustCompile(`^SUP-\d{4}-\d{4,}$`)
	for n := range results {
		if seen[n] || !pattern.MatchString(n) {
			t.Fatalf("invalid or duplicate number %q", n)
		}
		seen[n] = true
	}
	if len(seen) != 24 {
		t.Fatal("missing concurrent inserts")
	}
	// Number allocation rolls back with the business record, so a failed transaction
	// cannot leave a half-saved supplier or advance its committed counter.
	tx, e := pool.Begin(ctx)
	if e != nil {
		t.Fatal(e)
	}
	var rolled string
	if e = tx.QueryRow(ctx, "INSERT INTO app.suppliers(code,name) VALUES('','Rolled back supplier') RETURNING code").Scan(&rolled); e != nil {
		t.Fatal(e)
	}
	if e = tx.Rollback(ctx); e != nil {
		t.Fatal(e)
	}
	var next string
	if e = pool.QueryRow(ctx, "INSERT INTO app.suppliers(code,name) VALUES('','Committed supplier') RETURNING code").Scan(&next); e != nil {
		t.Fatal(e)
	}
	if rolled != next {
		t.Fatalf("rollback allocated %s but next was %s", rolled, next)
	}
	// Explicit legacy/import identifiers stay intact and reserve matching numbers.
	var year int
	if e = pool.QueryRow(ctx, "SELECT extract(year FROM app.business_date())::int").Scan(&year); e != nil {
		t.Fatal(e)
	}
	manual := fmt.Sprintf("SUP-%d-9999", year)
	if e = pool.QueryRow(ctx, "INSERT INTO app.suppliers(code,name) VALUES($1,'Imported supplier') RETURNING code", manual).Scan(&next); e != nil {
		t.Fatal(e)
	}
	if next != manual {
		t.Fatal("legacy number changed")
	}
	if e = pool.QueryRow(ctx, "INSERT INTO app.suppliers(code,name) VALUES('','After import') RETURNING code").Scan(&next); e != nil {
		t.Fatal(e)
	}
	if next != fmt.Sprintf("SUP-%d-10000", year) {
		t.Fatalf("number truncated or collided: %s", next)
	}
}
