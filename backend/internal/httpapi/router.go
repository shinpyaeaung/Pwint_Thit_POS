package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

type DatabaseChecker interface {
	CheckDatabase(context.Context) (int32, error)
}

func New(db DatabaseChecker, logger *slog.Logger, authorization *authz.Service, authentication ...*authn.Service) *gin.Engine {
	r := gin.New()
	_ = r.SetTrustedProxies(nil)
	r.Use(func(c *gin.Context) {
		var id [16]byte
		_, _ = rand.Read(id[:])
		requestID := hex.EncodeToString(id[:])
		c.Set("request_id", requestID)
		c.Header("X-Request-ID", requestID)
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("Cache-Control", "no-store")
		start := time.Now()
		c.Next()
		logger.Info("http request", "request_id", requestID, "method", c.Request.Method, "path", c.Request.URL.Path, "status", c.Writer.Status(), "duration_ms", time.Since(start).Milliseconds())
	})
	r.Use(func(c *gin.Context) {
		defer func() {
			if recover() != nil {
				logger.Error("request panic", "request_id", c.GetString("request_id"))
				failure(c, http.StatusInternalServerError, "internal_error", "An unexpected error occurred.")
			}
		}()
		c.Next()
	})
	if len(authentication) > 0 && authentication[0] != nil {
		a := authentication[0]
		r.Use(a.SameOrigin())
		r.POST("/api/v1/auth/login", a.Login)
		r.POST("/api/v1/auth/logout", a.Logout)
		r.GET("/api/v1/auth/me", authorization.Authenticate(), a.Current)
		r.GET("/api/v1/users", authorization.Require(permissions.UsersManage), a.Users)
		r.POST("/api/v1/users", authorization.Require(permissions.UsersManage), a.CreateStaff)
		r.GET("/api/v1/users/:id/permissions", authorization.Require(permissions.PermissionsManage), authorization.SuperAdminOnly(), a.UserPermissions)
		r.PUT("/api/v1/users/:id/permissions", authorization.Require(permissions.PermissionsManage), authorization.SuperAdminOnly(), a.SetPermissions)
	}
	r.GET("/api/v1/health/live", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "ok"}) })
	r.GET("/api/v1/health", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()
		ok, err := db.CheckDatabase(ctx)
		if err != nil || ok != 1 {
			logger.Warn("database health check failed", "request_id", c.GetString("request_id"))
			failure(c, http.StatusServiceUnavailable, "database_unavailable", "Database connection is unavailable.")
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "pwint-thit-api", "database": "connected"})
	})
	r.GET("/api/v1/permissions", authorization.Require(permissions.PermissionsManage), func(c *gin.Context) { authorization.ListPermissions(c) })
	r.NoRoute(func(c *gin.Context) {
		failure(c, http.StatusNotFound, "not_found", "The requested endpoint does not exist.")
	})
	r.HandleMethodNotAllowed = true
	r.NoMethod(func(c *gin.Context) {
		failure(c, http.StatusMethodNotAllowed, "method_not_allowed", "This method is not supported.")
	})
	return r
}

func failure(c *gin.Context, status int, code, message string) {
	c.AbortWithStatusJSON(status, gin.H{"error": gin.H{"code": code, "message": message, "request_id": c.GetString("request_id")}})
}
