// Package products owns catalog writes and their audit transaction boundaries.
package products

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

type DB interface {
	database.DBTX
	Begin(context.Context) (pgx.Tx, error)
}
type Service struct {
	db DB
	q  *database.Queries
}

func New(db DB) *Service { return &Service{db: db, q: database.New(db)} }
func (s *Service) Register(r *gin.Engine, a *authz.Service) {
	r.GET("/api/v1/products", a.Require(permissions.ProductsView), s.List)
	r.GET("/api/v1/products/:id", a.Require(permissions.ProductsView), s.Get)
	r.POST("/api/v1/products", a.Require(permissions.ProductsCreate), s.Save)
	r.PUT("/api/v1/products/:id", a.Require(permissions.ProductsUpdate), s.Save)
	r.DELETE("/api/v1/products/:id", a.Require(permissions.ProductsDelete), s.Archive)
	// Reference choices are needed by readers and by creators/updaters with separately assigned grants.
	r.GET("/api/v1/catalog", a.RequireAny(permissions.ProductsView, permissions.ProductsCreate, permissions.ProductsUpdate, permissions.CatalogManage), s.Metadata)
	for _, kind := range []string{"categories", "brands"} {
		r.POST("/api/v1/catalog/"+kind, a.Require(permissions.CatalogManage), s.SaveLookup(kind))
		r.PUT("/api/v1/catalog/"+kind+"/:id", a.Require(permissions.CatalogManage), s.SaveLookup(kind))
	}
	r.POST("/api/v1/catalog/units", a.Require(permissions.CatalogManage), s.CreateUnit)
}

type Pack struct {
	UnitCode        string `json:"unit_code"`
	UnitsPerPack    string `json:"units_per_pack"`
	Barcode         string `json:"barcode"`
	DefaultPurchase bool   `json:"is_default_purchase"`
	DefaultSale     bool   `json:"is_default_sale"`
}
type Input struct {
	SKU          string `json:"sku"`
	Name         string `json:"name"`
	Barcode      string `json:"barcode"`
	CategoryID   string `json:"category_id"`
	BrandID      string `json:"brand_id"`
	CountryCode  string `json:"country_code"`
	Description  string `json:"description"`
	BaseUnitCode string `json:"base_unit_code"`
	MinimumStock string `json:"minimum_stock"`
	TracksExpiry bool   `json:"tracks_expiry"`
	IsActive     *bool  `json:"is_active"`
	Version      string `json:"version"`
	Packaging    []Pack `json:"packaging"`
}

var skuPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$`)
var decimalPattern = regexp.MustCompile(`^[0-9]{1,14}(\.[0-9]{1,6})?$`)
var countryPattern = regexp.MustCompile(`^[A-Z]{2}$`)
var codePattern = regexp.MustCompile(`^[A-Z][A-Z0-9_]{0,19}$`)

func validDecimal(s string, positive bool) bool {
	if !decimalPattern.MatchString(s) {
		return false
	}
	n, ok := new(big.Rat).SetString(s)
	return ok && (!positive || n.Sign() > 0)
}
func uuid(s string) (pgtype.UUID, error) {
	var id pgtype.UUID
	if s == "" {
		return id, nil
	}
	err := id.Scan(s)
	return id, err
}
func validBarcode(s string) bool {
	if len(s) > 100 {
		return false
	}
	for _, r := range s {
		if r < 33 || r > 126 {
			return false
		}
	}
	return true
}
func (in *Input) validate() string {
	in.SKU = strings.TrimSpace(in.SKU)
	in.Name = strings.TrimSpace(in.Name)
	in.Barcode = strings.TrimSpace(in.Barcode)
	in.CountryCode = strings.ToUpper(strings.TrimSpace(in.CountryCode))
	if !skuPattern.MatchString(in.SKU) {
		return "SKU must be 1–100 letters, numbers, dots, underscores, hyphens or slashes."
	}
	if len(in.Name) == 0 || len(in.Name) > 200 || len(in.Description) > 4000 {
		return "Enter a product name (up to 200 bytes) and description (up to 4000 bytes)."
	}
	if in.IsActive == nil {
		return "Supply the product status."
	}
	if !validBarcode(in.Barcode) {
		return "Barcodes must contain at most 100 printable ASCII characters without spaces."
	}
	if in.CountryCode != "" && !countryPattern.MatchString(in.CountryCode) {
		return "Country must be a two-letter code."
	}
	if in.MinimumStock != "" && !validDecimal(in.MinimumStock, false) {
		return "Minimum stock must be non-negative with at most 14 whole digits and 6 decimal places."
	}
	for _, v := range []string{in.CategoryID, in.BrandID} {
		if _, e := uuid(v); e != nil {
			return "Invalid category or brand ID."
		}
	}
	if !codePattern.MatchString(in.BaseUnitCode) || len(in.Packaging) == 0 || len(in.Packaging) > 20 {
		return "Supply a base unit and 1–20 packaging units."
	}
	seen := map[string]bool{}
	barcodes := map[string]bool{}
	if in.Barcode != "" {
		barcodes[in.Barcode] = true
	}
	purchase, sale := 0, 0
	hasBase := false
	for i := range in.Packaging {
		p := &in.Packaging[i]
		p.Barcode = strings.TrimSpace(p.Barcode)
		if seen[p.UnitCode] || !codePattern.MatchString(p.UnitCode) || !validDecimal(p.UnitsPerPack, true) {
			return "Packaging units must be unique, with positive conversions of at most 6 decimal places."
		}
		seen[p.UnitCode] = true
		if !validBarcode(p.Barcode) || (p.Barcode != "" && barcodes[p.Barcode]) {
			return "Each product and packaging barcode must be distinct."
		}
		if p.Barcode != "" {
			barcodes[p.Barcode] = true
		}
		if p.UnitCode == in.BaseUnitCode {
			n, _ := new(big.Rat).SetString(p.UnitsPerPack)
			if n.Cmp(big.NewRat(1, 1)) != 0 {
				return "The base unit conversion must equal 1."
			}
			hasBase = true
		}
		if p.DefaultPurchase {
			purchase++
		}
		if p.DefaultSale {
			sale++
		}
	}
	if !hasBase || purchase != 1 || sale != 1 {
		return "Include the base unit and exactly one default purchase and sale unit."
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
			fail(c, 409, "That SKU, barcode, name or unit code already exists.")
			return
		case "23503", "23514", "22003", "22P02":
			fail(c, 400, "Invalid catalog reference, quantity or product data.")
			return
		}
	}
	fail(c, 503, "The catalog is unavailable. Please try again.")
}
func pathID(c *gin.Context) (pgtype.UUID, bool) {
	id, e := uuid(c.Param("id"))
	if e != nil || !id.Valid {
		fail(c, 400, "Invalid product or catalog ID.")
		return id, false
	}
	return id, true
}
func (s *Service) Metadata(c *gin.Context) {
	v, e := s.q.CatalogMetadata(c.Request.Context())
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", v)
}
func (s *Service) Get(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	v, e := s.q.GetProduct(c.Request.Context(), id)
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", v)
}
func (s *Service) List(c *gin.Context) {
	page, e := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, e2 := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	status := c.DefaultQuery("status", "all")
	search := strings.TrimSpace(c.Query("q"))
	category, e3 := uuid(c.Query("category_id"))
	brand, e4 := uuid(c.Query("brand_id"))
	if e != nil || e2 != nil || e3 != nil || e4 != nil || page < 1 || page > 100000 || size < 1 || size > 100 || len(search) > 200 || (status != "all" && status != "active" && status != "inactive" && status != "archived") {
		fail(c, 400, "Invalid search, filters or pagination.")
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	v, err := s.q.ListProducts(ctx, database.ListProductsParams{Status: status, CategoryID: category, BrandID: brand, Search: search, PageSize: int32(size), PageOffset: int32((page - 1) * size)})
	if err != nil {
		dbError(c, err)
		return
	}
	c.Data(200, "application/json", v)
}
func audit(ctx context.Context, q *database.Queries, c *gin.Context, id pgtype.UUID, kind, action string, before, after []byte) error {
	actor, _ := authz.Principal(c)
	return q.RecordProductAudit(ctx, database.RecordProductAuditParams{ActorID: actor.ID, Action: action, EntityType: kind, EntityID: id, OldValue: before, NewValue: after})
}
func (s *Service) Save(c *gin.Context) {
	var in Input
	if !decode(c, &in) {
		return
	}
	if message := in.validate(); message != "" {
		fail(c, 400, message)
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
	tx, err := s.db.Begin(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	if updating {
		old, e := q.LockProduct(ctx, id)
		if e != nil {
			dbError(c, e)
			return
		}
		if old.ArchivedAt.Valid {
			fail(c, 409, "Archived products cannot be edited.")
			return
		}
		if in.Version != strconv.FormatInt(old.Version, 10) {
			fail(c, 409, "This product changed. Reload its details before saving.")
			return
		}
		if old.BaseUnitCode != in.BaseUnitCode {
			used, e := q.ProductInUse(ctx, id)
			if e != nil {
				dbError(c, e)
				return
			}
			if used {
				fail(c, 409, "The base unit cannot change after this product is used in transactions.")
				return
			}
		}
		before, err = q.GetProduct(ctx, id)
		if err != nil {
			dbError(c, err)
			return
		}
	}
	category, _ := uuid(in.CategoryID)
	brand, _ := uuid(in.BrandID)
	valid, err := q.ProductReferencesValid(ctx, database.ProductReferencesValidParams{BaseUnit: in.BaseUnitCode, CategoryID: category, BrandID: brand})
	if err != nil {
		dbError(c, err)
		return
	}
	if !valid {
		fail(c, 400, "Select an existing unit and active category/brand.")
		return
	}
	data, _ := json.Marshal(in)
	if updating {
		err = q.UpdateProduct(ctx, database.UpdateProductParams{ID: id, Data: data})
	} else {
		id, err = q.InsertProduct(ctx, data)
	}
	if err != nil {
		dbError(c, err)
		return
	}
	if err = q.ResetProductDefaults(ctx, id); err != nil {
		dbError(c, err)
		return
	}
	codes := make([]string, 0, len(in.Packaging))
	for _, p := range in.Packaging {
		codes = append(codes, p.UnitCode)
	}
	if err = q.RemoveProductUnits(ctx, database.RemoveProductUnitsParams{ProductID: id, KeepCodes: codes}); err != nil {
		dbError(c, err)
		return
	}
	for _, p := range in.Packaging {
		var n pgtype.Numeric
		_ = n.Scan(p.UnitsPerPack)
		err = q.UpsertProductUnit(ctx, database.UpsertProductUnitParams{ProductID: id, UnitCode: p.UnitCode, UnitsPerPack: n, Barcode: pgtype.Text{String: p.Barcode, Valid: p.Barcode != ""}, IsDefaultPurchase: p.DefaultPurchase, IsDefaultSale: p.DefaultSale})
		if err != nil {
			dbError(c, err)
			return
		}
	}
	after, err := q.GetProduct(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	action := "products.create"
	status := 201
	if updating {
		action = "products.update"
		status = 200
	}
	if err = audit(ctx, q, c, id, "products", action, before, after); err != nil {
		dbError(c, err)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		dbError(c, err)
		return
	}
	c.Data(status, "application/json", after)
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
	ctx := c.Request.Context()
	tx, err := s.db.Begin(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	old, err := q.LockProduct(ctx, id)
	if err != nil {
		dbError(c, err)
		return
	}
	if in.Version != strconv.FormatInt(old.Version, 10) || old.ArchivedAt.Valid {
		fail(c, 409, "The product changed or is already archived. Reload its details.")
		return
	}
	before, err := q.GetProduct(ctx, id)
	if err == nil {
		err = q.ArchiveProduct(ctx, id)
	}
	if err != nil {
		dbError(c, err)
		return
	}
	after, err := q.GetProduct(ctx, id)
	if err == nil {
		err = audit(ctx, q, c, id, "products", "products.archive", before, after)
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
