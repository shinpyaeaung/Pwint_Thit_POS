package main

import (
	"context"
	"github.com/jackc/pgx/v5"
	"github.com/joho/godotenv"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/migrate"
	"log/slog"
	"os"
	"time"
)

func main() {
	if err := run(); err != nil {
		slog.Error("migration failed", "error", err)
		os.Exit(1)
	}
}
func run() error {
	_ = godotenv.Load("../.env")
	path := "../database/migrations"
	if len(os.Args) > 1 {
		path = os.Args[1]
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	conn, err := pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer conn.Close(context.Background())
	if err = migrate.Up(ctx, conn, os.DirFS(path)); err != nil {
		return err
	}
	slog.Info("database migrations are up to date")
	return nil
}
