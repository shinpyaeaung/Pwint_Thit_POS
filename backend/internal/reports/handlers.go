package reports

import (
	"context"
	"log/slog"
	"net/url"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

type Handler struct {
	service       *Service
	authorization *authz.Service
}

func Register(router *gin.Engine, db database.DBTX, authorization *authz.Service) {
	h := &Handler{service: NewService(NewRepository(db)), authorization: authorization}
	group := router.Group("/api/v1/reports", authorization.Require(permissions.ReportsView))
	group.GET("", h.catalog)
	for _, definition := range definitions {
		definition := definition
		group.GET("/"+definition.ID, h.requireReport(definition.ID), func(c *gin.Context) { h.report(c, definition) })
	}
	group.GET("/:report", func(c *gin.Context) {
		reportError(c, 404, "report_not_found", "Choose an available report.")
	})
}
func (h *Handler) catalog(c *gin.Context) {
	if c.Request.URL.RawQuery != "" {
		reportError(c, 400, "invalid_filter", "The report catalog does not accept filters.")
		return
	}
	visible := make([]Definition, 0)
	for _, definition := range definitions {
		allowed, err := h.allowed(c, definition.ID)
		if err != nil {
			reportError(c, 503, "authorization_unavailable", "Report authorization is unavailable.")
			return
		}
		if allowed {
			visible = append(visible, definition)
		}
	}
	c.JSON(200, gin.H{"reports": visible})
}
func (h *Handler) report(c *gin.Context, definition Definition) {
	values, err := url.ParseQuery(c.Request.URL.RawQuery)
	if err != nil {
		reportError(c, 400, "invalid_filter", "Malformed report filters.")
		return
	}
	filter, err := ValidateFilter(values, time.Now())
	if err != nil {
		reportError(c, 400, "invalid_filter", err.Error())
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()
	response, err := h.service.Run(ctx, definition, filter)
	if err != nil {
		slog.Error("report unavailable", "report", definition.ID, "error", err)
		reportError(c, 503, "report_unavailable", "The report could not be loaded. Please try again.")
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(200, response)
}
func reportError(c *gin.Context, status int, code, message string) {
	c.AbortWithStatusJSON(status, gin.H{"error": gin.H{"code": code, "message": message, "request_id": c.GetString("request_id")}})
}
