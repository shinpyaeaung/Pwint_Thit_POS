package config

import (
	"fmt"
	"log/slog"
	"net"
	"net/url"
	"os"
	"strings"
)

type Config struct {
	Environment    string
	HTTPAddr       string
	DatabaseURL    string
	LogLevel       slog.Level
	AllowedOrigins []string
	SecureCookie   bool
}

func Load() (Config, error) {
	c := Config{Environment: value("APP_ENV", "development"), HTTPAddr: value("HTTP_ADDR", "127.0.0.1:8080"), DatabaseURL: os.Getenv("DATABASE_URL")}
	if c.Environment != "development" && c.Environment != "test" && c.Environment != "production" {
		return c, fmt.Errorf("APP_ENV must be development, test, or production")
	}
	if _, _, err := net.SplitHostPort(c.HTTPAddr); err != nil {
		return c, fmt.Errorf("HTTP_ADDR must be host:port")
	}
	u, err := url.Parse(c.DatabaseURL)
	if err != nil || u == nil || (u.Scheme != "postgres" && u.Scheme != "postgresql") || u.Hostname() == "" || strings.Trim(u.Path, "/") == "" {
		return c, fmt.Errorf("DATABASE_URL must be a PostgreSQL URL with host and database")
	}
	if err := c.LogLevel.UnmarshalText([]byte(value("LOG_LEVEL", "info"))); err != nil {
		return c, fmt.Errorf("LOG_LEVEL must be debug, info, warn, or error")
	}
	c.SecureCookie = c.Environment == "production"
	origins := os.Getenv("ALLOWED_ORIGINS")
	if origins == "" && c.Environment != "production" {
		origins = "http://127.0.0.1:5173,http://localhost:5173,http://127.0.0.1:8088,http://localhost:8088"
	}
	if origins == "" {
		return c, fmt.Errorf("ALLOWED_ORIGINS is required in production")
	}
	for _, origin := range strings.Split(origins, ",") {
		origin = strings.TrimSpace(origin)
		u, err := url.Parse(origin)
		if err != nil || u.Host == "" || u.User != nil || u.Path != "" || u.RawQuery != "" || u.Fragment != "" || (u.Scheme != "http" && u.Scheme != "https") || (c.SecureCookie && u.Scheme != "https") {
			return c, fmt.Errorf("ALLOWED_ORIGINS must contain explicit origins; production requires HTTPS")
		}
		c.AllowedOrigins = append(c.AllowedOrigins, origin)
	}
	return c, nil
}

func value(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
