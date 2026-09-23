// Package suppliers owns supplier records and read-only purchase history.
package suppliers

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type DB interface {
	database.DBTX
	Begin(context.Context) (pgx.Tx, error)
}
type Service struct {
	db            DB
	q             *database.Queries
	authorization *authz.Service
}

func New(db DB) *Service { return &Service{db: db, q: database.New(db)} }
func (s *Service) Register(r *gin.Engine, a *authz.Service) {
	s.authorization = a
	r.GET("/api/v1/suppliers", a.Require(permissions.SuppliersView), s.List)
	r.GET("/api/v1/suppliers/:id", a.Require(permissions.SuppliersView), s.Get)
	r.POST("/api/v1/suppliers", a.Require(permissions.SuppliersCreate), s.Save)
	r.PUT("/api/v1/suppliers/:id", a.Require(permissions.SuppliersUpdate), s.Save)
	r.DELETE("/api/v1/suppliers/:id", a.Require(permissions.SuppliersDelete), s.Archive)
	r.GET("/api/v1/suppliers/:id/purchases", a.Require(permissions.SuppliersView), a.Require(permissions.PurchasesView), s.History)
}

type Input struct {
	Code          string `json:"code"`
	Name          string `json:"name"`
	ContactPerson string `json:"contact_person"`
	Phone         string `json:"phone"`
	Address       string `json:"address"`
	CountryCode   string `json:"country_code"`
	SupplierType  string `json:"supplier_type"`
	PaymentTerms  string `json:"payment_terms"`
	Notes         string `json:"notes"`
	IsActive      *bool  `json:"is_active"`
	Version       string `json:"version"`
}

var codePattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$`)
var countryPattern = regexp.MustCompile(`^[A-Z]{2}$`)

func uuid(s string) (pgtype.UUID, error) { var id pgtype.UUID; err := id.Scan(s); return id, err }
func (in *Input) validate() string {
	in.Code = strings.TrimSpace(in.Code)
	in.Name = strings.TrimSpace(in.Name)
	in.CountryCode = strings.ToUpper(strings.TrimSpace(in.CountryCode))
	if !codePattern.MatchString(in.Code) {
		return "Supplier code must be 1–100 letters, numbers, dots, underscores, hyphens or slashes."
	}
	if in.Name == "" || len(in.Name) > 200 {
		return "Enter a supplier name of up to 200 bytes."
	}
	if in.IsActive == nil {
		return "Supply the supplier status."
	}
	if in.CountryCode != "" && !countryPattern.MatchString(in.CountryCode) {
		return "Country must be a two-letter code."
	}
	if len(in.ContactPerson) > 200 || len(in.Phone) > 100 || len(in.Address) > 2000 || len(in.SupplierType) > 100 || len(in.PaymentTerms) > 2000 || len(in.Notes) > 4000 {
		return "Contact details, payment terms or notes exceed the allowed length."
	}
	return ""
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
		switch pe.Code {
		case "23505":
			fail(c, 409, "That supplier code already exists.")
			return
		case "23503", "23514", "22003", "22P02":
			fail(c, 400, "Invalid supplier data.")
			return
		}
	}
	fail(c, 503, "Supplier data is unavailable. Please try again.")
}
func pathID(c *gin.Context) (pgtype.UUID, bool) {
	id, e := uuid(c.Param("id"))
	if e != nil || !id.Valid {
		fail(c, 400, "Invalid supplier ID.")
		return id, false
	}
	return id, true
}
func (s *Service) Get(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	v, e := s.q.GetSupplier(c.Request.Context(), id)
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", v)
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
func (s *Service) List(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	status := c.DefaultQuery("status", "all")
	search := strings.TrimSpace(c.Query("q"))
	country := strings.ToUpper(strings.TrimSpace(c.Query("country")))
	if len(search) > 200 || (country != "" && !countryPattern.MatchString(country)) || (status != "all" && status != "active" && status != "inactive" && status != "archived") {
		fail(c, 400, "Invalid search or filters.")
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	v, e := s.q.ListSuppliers(ctx, database.ListSuppliersParams{Status: status, Search: search, Country: country, PageSize: size, PageOffset: offset})
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", v)
}
func (s *Service) History(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	if _, e := s.q.GetSupplier(ctx, id); e != nil {
		dbError(c, e)
		return
	}
	allowed, e := s.authorization.Allowed(c, permissions.PurchasesViewCost)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return
	}
	v, e := s.q.SupplierPurchaseHistory(ctx, database.SupplierPurchaseHistoryParams{SupplierID: id, PageSize: size, PageOffset: offset, ViewCost: allowed})
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", v)
}
func (s *Service) Save(c *gin.Context) {
	var in Input
	if !decode(c, &in) {
		return
	}
	if msg := in.validate(); msg != "" {
		fail(c, 400, msg)
		return
	}
	updating := c.Request.Method == http.MethodPut
	var id pgtype.UUID
	var before []byte
	if updating {
		var ok bool
		id, ok = pathID(c)
		if !ok {
			return
		}
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	if updating {
		old, err := q.LockSupplier(ctx, id)
		if err != nil {
			dbError(c, err)
			return
		}
		if old.ArchivedAt.Valid || in.Version != strconv.FormatInt(old.Version, 10) {
			fail(c, 409, "Supplier changed or is archived. Reload its details before saving.")
			return
		}
		before, e = q.GetSupplier(ctx, id)
		if e != nil {
			dbError(c, e)
			return
		}
	}
	data, _ := json.Marshal(in)
	if updating {
		e = q.UpdateSupplier(ctx, database.UpdateSupplierParams{ID: id, Data: data})
	} else {
		id, e = q.InsertSupplier(ctx, data)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	after, e := q.GetSupplier(ctx, id)
	if e != nil {
		dbError(c, e)
		return
	}
	action := "suppliers.create"
	status := 201
	if updating {
		action = "suppliers.update"
		status = 200
	}
	if e = audit(ctx, q, c, id, action, before, after); e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(status, "application/json", after)
}
func audit(ctx context.Context, q *database.Queries, c *gin.Context, id pgtype.UUID, action string, before, after []byte) error {
	actor, _ := authz.Principal(c)
	return q.RecordProductAudit(ctx, database.RecordProductAuditParams{ActorID: actor.ID, Action: action, EntityType: "suppliers", EntityID: id, OldValue: before, NewValue: after})
}
func (s *Service) Archive(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	var in struct {
		Version string `json:"version"`
	}
	if !decode(c, &in) {
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()
	tx, err := s.db.Begin(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	old, err := q.LockSupplier(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if in.Version != strconv.FormatInt(old.Version, 10) || old.ArchivedAt.Valid {
		fail(c, 409, "The supplier changed or is already archived. Reload its details.")
		return
	}
	before, err := q.GetSupplier(ctx, id)
	if err == nil {
		err = q.ArchiveSupplier(ctx, id)
	}
	if err != nil {
		dbError(c, err)
		return
	}
	after, err := q.GetSupplier(ctx, id)
	if err == nil {
		err = audit(ctx, q, c, id, "suppliers.archive", before, after)
	}
	if err == nil {
		err = tx.Commit(ctx)
	}
	if err != nil {
		dbError(c, err)
		return
	}
	c.Status(204)
}
