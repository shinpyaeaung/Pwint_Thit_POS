// Package migrate applies ordered, checksummed SQL migrations atomically.
package migrate

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"regexp"
	"sort"

	"github.com/jackc/pgx/v5"
)

var filename = regexp.MustCompile(`^[0-9]{6}_[a-z0-9_]+\.sql$`)

func Up(ctx context.Context, conn *pgx.Conn, source fs.FS) error {
	entries, err := fs.ReadDir(source, ".")
	if err != nil {
		return err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && filename.MatchString(e.Name()) {
			names = append(names, e.Name())
		}
	}
	if len(names) == 0 {
		return fmt.Errorf("no SQL migrations found")
	}
	sort.Strings(names)
	for i, name := range names {
		if name[:6] != fmt.Sprintf("%06d", i+1) {
			return fmt.Errorf("migration versions must be unique and consecutive: %s", name)
		}
	}
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())
	if _, err = tx.Exec(ctx, `SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='60s'; SELECT pg_advisory_xact_lock(7359202602); CREATE TABLE IF NOT EXISTS public.schema_migrations (version text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now());`); err != nil {
		return err
	}
	rows, err := tx.Query(ctx, "SELECT version,checksum FROM public.schema_migrations ORDER BY version")
	if err != nil {
		return err
	}
	applied := map[string]string{}
	for rows.Next() {
		var name, hash string
		if err = rows.Scan(&name, &hash); err != nil {
			rows.Close()
			return err
		}
		applied[name] = hash
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return err
	}
	known := map[string]bool{}
	for _, name := range names {
		known[name] = true
	}
	for name := range applied {
		if !known[name] {
			return fmt.Errorf("applied migration missing from source: %s", name)
		}
	}
	for _, name := range names {
		sql, err := fs.ReadFile(source, name)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(sql)
		hash := hex.EncodeToString(sum[:])
		if previous, ok := applied[name]; ok {
			if previous != hash {
				return fmt.Errorf("applied migration checksum mismatch: %s", name)
			}
			continue
		}
		if _, err = tx.Exec(ctx, string(sql)); err != nil {
			return fmt.Errorf("migration %s: %w", name, err)
		}
		if _, err = tx.Exec(ctx, "INSERT INTO public.schema_migrations(version,checksum) VALUES($1,$2)", name, hash); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
