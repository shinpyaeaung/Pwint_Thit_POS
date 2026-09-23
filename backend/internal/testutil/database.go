package testutil

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"github.com/jackc/pgx/v5"
	"os"
	"testing"
	"time"
)

// Database creates a disposable database; tests never reset the application's database.
func Database(t *testing.T) *pgx.Conn {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("set TEST_DATABASE_URL for PostgreSQL integration tests")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cfg, err := pgx.ParseConfig(url)
	if err != nil {
		t.Fatal("invalid test database URL")
	}
	admin, err := pgx.ConnectConfig(ctx, cfg)
	if err != nil {
		t.Fatal("cannot connect to test database server")
	}
	var random [8]byte
	_, err = rand.Read(random[:])
	if err != nil {
		t.Fatal(err)
	}
	name := "pwint_test_" + hex.EncodeToString(random[:])
	identifier := pgx.Identifier{name}.Sanitize()
	if _, err = admin.Exec(ctx, "CREATE DATABASE "+identifier); err != nil {
		admin.Close(context.Background())
		t.Fatalf("test role needs CREATEDB: %v", err)
	}
	testCfg := cfg.Copy()
	testCfg.Database = name
	conn, err := pgx.ConnectConfig(ctx, testCfg)
	t.Cleanup(func() {
		if conn != nil {
			conn.Close(context.Background())
		}
		_, _ = admin.Exec(context.Background(), "DROP DATABASE "+identifier+" WITH (FORCE)")
		admin.Close(context.Background())
	})
	if err != nil {
		t.Fatal(err)
	}
	return conn
}
