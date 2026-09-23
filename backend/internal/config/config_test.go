package config

import "testing"

func TestLoad(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:secret@localhost:5432/pwint_thit")
	t.Setenv("APP_ENV", "")
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("LOG_LEVEL", "")
	c, err := Load()
	if err != nil || c.HTTPAddr != "127.0.0.1:8080" {
		t.Fatalf("defaults: %+v %v", c, err)
	}
	for _, tt := range []struct{ key, value string }{
		{"DATABASE_URL", ""}, {"DATABASE_URL", "https://example.com/db"}, {"DATABASE_URL", "postgres://localhost"},
		{"HTTP_ADDR", "broken"}, {"LOG_LEVEL", "verbose"}, {"APP_ENV", "unknown"},
	} {
		t.Run(tt.key+tt.value, func(t *testing.T) {
			t.Setenv(tt.key, tt.value)
			if _, err := Load(); err == nil {
				t.Fatal("expected invalid configuration to fail")
			}
		})
	}
}

func TestProductionOrigins(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://user:secret@localhost:5432/test")
	t.Setenv("APP_ENV", "production")
	t.Setenv("HTTP_ADDR", "127.0.0.1:8080")
	t.Setenv("LOG_LEVEL", "info")
	for _, origin := range []string{"", "http://example.com", "https://example.com/path", "https://user@example.com", "*"} {
		t.Setenv("ALLOWED_ORIGINS", origin)
		if _, err := Load(); err == nil {
			t.Fatalf("accepted unsafe production origin %q", origin)
		}
	}
	t.Setenv("ALLOWED_ORIGINS", "https://example.com")
	cfg, err := Load()
	if err != nil || !cfg.SecureCookie || len(cfg.AllowedOrigins) != 1 {
		t.Fatalf("production configuration: %v", err)
	}
}
