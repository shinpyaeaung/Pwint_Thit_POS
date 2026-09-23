// Package authz enforces server-side session authentication and per-user permissions.
package authz

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

type Store interface {
	AuthenticateSession(context.Context, []byte) (database.AuthenticateSessionRow, error)
	HasPermission(context.Context, database.HasPermissionParams) (bool, error)
	ListPermissions(context.Context) ([]database.ListPermissionsRow, error)
}

type Service struct{ store Store }

func New(store Store) *Service { return &Service{store: store} }

const CookieName = "pwint_session"
const principalKey = "pwint.authenticated_user"

func Principal(c *gin.Context) (database.AuthenticateSessionRow, bool) {
	value, ok := c.Get(principalKey)
	if !ok {
		return database.AuthenticateSessionRow{}, false
	}
	user, ok := value.(database.AuthenticateSessionRow)
	return user, ok
}

func Token(c *gin.Context) string {
	if header := c.GetHeader("Authorization"); header != "" {
		scheme, token, ok := strings.Cut(header, " ")
		if !ok || !strings.EqualFold(scheme, "Bearer") {
			return ""
		}
		return validToken(token)
	}
	token, _ := c.Cookie(CookieName)
	return validToken(token)
}
func validToken(token string) string {
	raw, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(raw) != 32 {
		return ""
	}
	return token
}

func (s *Service) authenticate(c *gin.Context) bool {
	if s == nil || s.store == nil {
		deny(c, 503, "authorization_unavailable")
		return false
	}
	if _, ok := Principal(c); ok {
		return true
	}
	token := Token(c)
	if token == "" {
		deny(c, 401, "unauthorized")
		return false
	}
	hash := sha256.Sum256([]byte(token))
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	user, err := s.store.AuthenticateSession(ctx, hash[:])
	if errors.Is(err, pgx.ErrNoRows) {
		deny(c, 401, "unauthorized")
		return false
	}
	if err != nil {
		deny(c, 503, "authorization_unavailable")
		return false
	}
	c.Set(principalKey, user)
	return true
}
func (s *Service) Authenticate() gin.HandlerFunc {
	return func(c *gin.Context) {
		if s.authenticate(c) {
			c.Next()
		}
	}
}

// Require checks current grants in PostgreSQL; handlers never implement their own role checks.
func (s *Service) Require(permission permissions.Code) gin.HandlerFunc {
	return s.RequireAny(permission)
}

// RequireAny centralizes alternative access policies for shared reference data.
func (s *Service) RequireAny(codes ...permissions.Code) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !s.authenticate(c) {
			return
		}
		user, _ := Principal(c)
		ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
		defer cancel()
		for _, code := range codes {
			allowed, err := s.store.HasPermission(ctx, database.HasPermissionParams{ID: user.ID, Code: string(code)})
			if err != nil {
				deny(c, 503, "authorization_unavailable")
				return
			}
			if allowed {
				c.Next()
				return
			}
		}
		deny(c, 403, "forbidden")
	}
}

// Grant administration is owner-only, preventing a delegated user manager from escalating privileges.
func (s *Service) SuperAdminOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !s.authenticate(c) {
			return
		}
		user, _ := Principal(c)
		if user.RoleCode != permissions.SuperAdmin {
			deny(c, 403, "forbidden")
			return
		}
		c.Next()
	}
}

func (s *Service) ListPermissions(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	rows, err := s.store.ListPermissions(ctx)
	if err != nil {
		deny(c, http.StatusServiceUnavailable, "authorization_unavailable")
		return
	}
	type permission struct {
		Code        string `json:"code"`
		Description string `json:"description"`
		Sensitive   bool   `json:"sensitive"`
	}
	out := make([]permission, 0, len(rows))
	for _, r := range rows {
		out = append(out, permission{r.Code, r.Description, r.IsSensitive})
	}
	c.JSON(http.StatusOK, gin.H{"permissions": out})
}
func deny(c *gin.Context, status int, code string) {
	c.AbortWithStatusJSON(status, gin.H{"error": gin.H{"code": code, "message": http.StatusText(status), "request_id": c.GetString("request_id")}})
}
