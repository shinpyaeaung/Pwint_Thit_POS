package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

type checkStub struct {
	result     int32
	err        error
	panicValue bool
}

func (s checkStub) CheckDatabase(ctx context.Context) (int32, error) {
	if _, ok := ctx.Deadline(); !ok {
		panic("missing deadline")
	}
	if s.panicValue {
		panic("secret database details")
	}
	return s.result, s.err
}

func TestRoutes(t *testing.T) {
	for _, tt := range []struct {
		name, method, path string
		db                 checkStub
		status             int
		code               string
	}{
		{"ready", "GET", "/api/v1/health", checkStub{result: 1}, 200, ""},
		{"unavailable", "GET", "/api/v1/health", checkStub{err: errors.New("private connection string")}, 503, "database_unavailable"},
		{"invalid result", "GET", "/api/v1/health", checkStub{}, 503, "database_unavailable"},
		{"live without database", "GET", "/api/v1/health/live", checkStub{}, 200, ""},
		{"missing route", "GET", "/missing", checkStub{}, 404, "not_found"},
		{"wrong method", "POST", "/api/v1/health", checkStub{}, 405, "method_not_allowed"},
		{"recovery", "GET", "/api/v1/health", checkStub{panicValue: true}, 500, "internal_error"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			r := New(tt.db, slog.New(slog.NewJSONHandler(io.Discard, nil)), nil)
			w := httptest.NewRecorder()
			r.ServeHTTP(w, httptest.NewRequest(tt.method, tt.path, nil))
			if w.Code != tt.status {
				t.Fatalf("status = %d; want %d", w.Code, tt.status)
			}
			if w.Header().Get("X-Request-ID") == "" {
				t.Fatal("missing request ID")
			}
			var body struct {
				Status   string `json:"status"`
				Database string `json:"database"`
				Error    struct {
					Code      string `json:"code"`
					RequestID string `json:"request_id"`
				} `json:"error"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			if body.Error.Code != tt.code {
				t.Fatalf("error = %q; want %q", body.Error.Code, tt.code)
			}
			if tt.code != "" && body.Error.RequestID != w.Header().Get("X-Request-ID") {
				t.Fatal("error request ID mismatch")
			}
			if tt.status == http.StatusOK && body.Status != "ok" {
				t.Fatal("missing health status")
			}
			if tt.name == "ready" && body.Database != "connected" {
				t.Fatal("missing database status")
			}
		})
	}
}
