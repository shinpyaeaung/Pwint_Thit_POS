package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/joho/godotenv"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/password"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"golang.org/x/term"
	"os"
	"strings"
	"time"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	username := flag.String("username", "admin", "Initial Super Admin username")
	name := flag.String("name", "Super Admin", "Display name")
	flag.Parse()
	if !authn.ValidUsername(*username) || strings.TrimSpace(*name) == "" {
		return errors.New("invalid username or display name")
	}
	fmt.Fprint(os.Stderr, "New password (minimum 12 characters): ")
	var raw []byte
	var err error
	if term.IsTerminal(int(os.Stdin.Fd())) {
		raw, err = term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
	} else {
		var line string
		line, err = bufio.NewReader(os.Stdin).ReadString('\n')
		if err == nil {
			raw = []byte(strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r"))
		}
	}
	if err != nil {
		return errors.New("could not read password from stdin")
	}
	hash, err := password.Hash(string(raw))
	clear(raw)
	if err != nil {
		return err
	}
	_ = godotenv.Load("../.env")
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	conn, err := pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return errors.New("database unavailable; run migrations first")
	}
	defer conn.Close(context.Background())
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())
	if _, err = tx.Exec(ctx, "SELECT pg_advisory_xact_lock(7359202603)"); err != nil {
		return err
	}
	var exists bool
	if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM app.users WHERE role_code='SUPER_ADMIN')").Scan(&exists); err != nil {
		return err
	}
	if exists {
		return errors.New("a Super Admin already exists; bootstrap does not replace existing accounts")
	}
	q := database.New(tx)
	id, err := q.CreateUser(ctx, database.CreateUserParams{Username: *username, DisplayName: *name, PasswordHash: hash, RoleCode: permissions.SuperAdmin})
	if err != nil {
		return errors.New("could not create administrator; check username uniqueness")
	}
	if err = q.RecordAuthAudit(ctx, database.RecordAuthAuditParams{ActorID: id, EntityID: id, Action: "users.bootstrap", Reason: pgtype.Text{String: "Initial Super Admin created by local operator", Valid: true}}); err != nil {
		return err
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	fmt.Println("Super Admin created. Sign in using the password you entered.")
	return nil
}
