package finance

import (
	"encoding/json"
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"io"
	"net/http"
	"strconv"
	"strings"
)

func uuid(s string) (pgtype.UUID, error) {
	var id pgtype.UUID
	if s == "" {
		return id, nil
	}
	e := id.Scan(s)
	return id, e
}
func decode(c *gin.Context, v any) bool {
	if c.ContentType() != "application/json" {
		fail(c, 415, "Send a JSON request.")
		return false
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64*1024)
	d := json.NewDecoder(c.Request.Body)
	d.DisallowUnknownFields()
	if d.Decode(v) != nil || d.Decode(new(any)) != io.EOF {
		fail(c, 400, "Invalid request fields or JSON body.")
		return false
	}
	return true
}
func fail(c *gin.Context, status int, message string) {
	c.AbortWithStatusJSON(status, gin.H{"error": gin.H{"code": http.StatusText(status), "message": message, "request_id": c.GetString("request_id")}})
}
func dbError(c *gin.Context, err error) {
	if errors.Is(err, pgx.ErrNoRows) {
		fail(c, 404, "Record not found.")
		return
	}
	var pe *pgconn.PgError
	if errors.As(err, &pe) {
		if pe.Code == "23514" && strings.HasPrefix(pe.Message, "finance: ") {
			fail(c, 409, strings.TrimPrefix(pe.Message, "finance: "))
			return
		}
		switch pe.Code {
		case "23505":
			fail(c, 409, "That request already exists. Retry its original details.")
			return
		case "23503", "23514", "22003", "22P02":
			fail(c, 400, "Invalid expense or payment data.")
			return
		}
	}
	fail(c, 503, "Finance data is unavailable. Please try again.")
}
func pathID(c *gin.Context) (pgtype.UUID, bool) {
	id, e := uuid(c.Param("id"))
	if e != nil || !id.Valid {
		fail(c, 400, "Invalid reference ID.")
		return id, false
	}
	return id, true
}
func pagination(c *gin.Context) (int32, int32, bool) {
	page, e := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, e2 := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if e != nil || e2 != nil || page < 1 || page > 100000 || size < 1 || size > 100 {
		fail(c, 400, "Invalid pagination.")
		return 0, 0, false
	}
	return int32(size), int32((page - 1) * size), true
}
