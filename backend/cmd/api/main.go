package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/config"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/httpapi"
)

func main() {
	if err := run(); err != nil {
		slog.Error("API stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	// Existing process environment always takes precedence over local files.
	if err := godotenv.Load("../.env"); err != nil && !errors.Is(err, os.ErrNotExist) {
		return errors.New("cannot load environment file")
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(logger)
	gin.SetMode(gin.ReleaseMode)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	poolCfg, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		return errors.New("invalid database configuration")
	}
	poolCfg.MaxConns = 10
	poolCfg.MinConns = 1
	poolCfg.ConnConfig.ConnectTimeout = 5 * time.Second
	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return errors.New("cannot create database pool")
	}
	defer pool.Close()
	startup, cancel := context.WithTimeout(ctx, 10*time.Second)
	err = pool.Ping(startup)
	cancel()
	if err != nil {
		return errors.New("database connection failed; check DATABASE_URL and PostgreSQL availability")
	}
	logger.Info("database connected")
	server := &http.Server{Addr: cfg.HTTPAddr, Handler: httpapi.New(database.New(pool), logger, authz.New(database.New(pool)), authn.New(pool, authn.Options{SecureCookie: cfg.SecureCookie, AllowedOrigins: cfg.AllowedOrigins})), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second}
	failures := make(chan error, 1)
	go func() {
		logger.Info("API listening", "address", cfg.HTTPAddr, "environment", cfg.Environment)
		failures <- server.ListenAndServe()
	}()
	select {
	case err := <-failures:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdown); err != nil {
			_ = server.Close()
			return err
		}
	}
	logger.Info("API stopped gracefully")
	return nil
}
