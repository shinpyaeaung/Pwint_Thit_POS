package purchasing

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"math/big"
	"regexp"
	"strings"
	"time"
)

type DB interface {
	database.DBTX
	Begin(context.Context) (pgx.Tx, error)
}
type Service struct {
	db DB
	q  *database.Queries
	a  *authz.Service
}

func New(db DB) *Service { return &Service{db: db, q: database.New(db)} }
func (s *Service) Register(r *gin.Engine, a *authz.Service) {
	s.a = a
	r.GET("/api/v1/currencies", a.RequireAny(permissions.PurchasesView, permissions.PurchasesCreate, permissions.ExchangeRatesManage, permissions.SettingsManage), s.Currencies)
	r.POST("/api/v1/currencies", a.Require(permissions.SettingsManage), s.CreateCurrency)
	r.GET("/api/v1/exchange-rates", a.RequireAny(permissions.PurchasesCreate, permissions.PurchasesViewCost, permissions.ExchangeRatesManage), s.Rates)
	r.POST("/api/v1/exchange-rates", a.Require(permissions.ExchangeRatesManage), s.CreateRate)
	r.GET("/api/v1/purchase-options", a.Require(permissions.PurchasesCreate), a.Require(permissions.PurchasesViewCost), s.Options)
	r.GET("/api/v1/purchases", a.Require(permissions.PurchasesView), s.List)
	r.GET("/api/v1/purchases/:id", a.Require(permissions.PurchasesView), s.Get)
	r.POST("/api/v1/purchases", a.Require(permissions.PurchasesCreate), a.Require(permissions.PurchasesViewCost), s.Create)
	r.GET("/api/v1/suppliers/:id/balance", a.Require(permissions.SuppliersView), a.Require(permissions.PurchasesViewCost), s.Balance)
}
func (s *Service) costs(c *gin.Context) (bool, bool) {
	v, e := s.a.Allowed(c, permissions.PurchasesViewCost)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return false, false
	}
	return v, true
}
func (s *Service) Currencies(c *gin.Context) {
	v, e := s.q.PurchaseCurrencies(c.Request.Context())
	respond(c, v, e)
}
func respond(c *gin.Context, v []byte, e error) {
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", v)
}
func (s *Service) Options(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if len(q) > 200 {
		fail(c, 400, "Search is too long.")
		return
	}
	var v []byte
	var e error
	switch c.Query("kind") {
	case "suppliers":
		v, e = s.q.PurchaseSupplierOptions(c.Request.Context(), q)
	case "products":
		v, e = s.q.PurchaseProductOptions(c.Request.Context(), q)
	default:
		fail(c, 400, "Choose suppliers or products.")
		return
	}
	respond(c, v, e)
}
func (s *Service) Get(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	cost, ok := s.costs(c)
	if !ok {
		return
	}
	v, e := s.q.GetPurchaseDocument(c.Request.Context(), database.GetPurchaseDocumentParams{ID: id, Costs: cost})
	respond(c, v, e)
}
func (s *Service) Balance(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	v, e := s.q.SupplierPurchaseBalance(c.Request.Context(), id)
	respond(c, v, e)
}
func (s *Service) List(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	cost, ok := s.costs(c)
	if !ok {
		return
	}
	search, currency, status := strings.TrimSpace(c.Query("q")), c.Query("currency"), c.Query("status")
	if len(search) > 200 || (currency != "" && !currencyPattern.MatchString(currency)) || (status != "" && status != "DRAFT" && status != "POSTED" && status != "CANCELLED" && status != "REVERSED") {
		fail(c, 400, "Invalid search or filters.")
		return
	}
	v, e := s.q.ListPurchaseDocuments(c.Request.Context(), database.ListPurchaseDocumentsParams{Search: search, Currency: currency, Status: status, PageSize: size, PageOffset: offset, Costs: cost})
	respond(c, v, e)
}

var currencyPattern = regexp.MustCompile(`^[A-Z]{3}$`)
var numberPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$`)

func decimal(v string, whole, scale int, positive bool) bool {
	parts := strings.Split(v, ".")
	if len(parts) > 2 || len(parts[0]) == 0 || len(parts[0]) > whole {
		return false
	}
	if len(parts) == 2 && (len(parts[1]) == 0 || len(parts[1]) > scale) {
		return false
	}
	for _, part := range parts {
		for _, ch := range part {
			if ch < '0' || ch > '9' {
				return false
			}
		}
	}
	n, ok := new(big.Rat).SetString(v)
	return ok && (!positive || n.Sign() > 0)
}
func sameNumber(a, b string) bool {
	x, ok := new(big.Rat).SetString(a)
	y, ok2 := new(big.Rat).SetString(b)
	return ok && ok2 && x.Cmp(y) == 0
}

type Item struct {
	ProductID    string `json:"product_id"`
	UnitCode     string `json:"unit_code"`
	Quantity     string `json:"quantity"`
	UnitsPerPack string `json:"units_per_pack"`
	UnitPrice    string `json:"unit_price_original"`
	Discount     string `json:"discount_original"`
	Tax          string `json:"tax_original"`
}
type Input struct {
	RequestID   string `json:"request_id"`
	Number      string `json:"purchase_number"`
	SupplierID  string `json:"supplier_id"`
	Invoice     string `json:"supplier_invoice_number"`
	PurchasedAt string `json:"purchased_at"`
	DueDate     string `json:"due_date"`
	Currency    string `json:"currency_code"`
	RateID      string `json:"exchange_rate_id"`
	Rate        string `json:"mmk_per_unit"`
	Notes       string `json:"notes"`
	Items       []Item `json:"items"`
}

func (in *Input) validate() string {
	in.Number = strings.TrimSpace(in.Number)
	in.Invoice = strings.TrimSpace(in.Invoice)
	if !numberPattern.MatchString(in.Number) || len(in.Invoice) > 200 || len(in.Notes) > 4000 {
		return "Enter a purchase number (up to 100 characters), invoice (200 bytes) and notes (4000 bytes)."
	}
	for _, v := range []string{in.RequestID, in.SupplierID} {
		id, e := uuid(v)
		if e != nil || !id.Valid {
			return "Invalid request or supplier ID."
		}
	}
	if _, e := uuid(in.RateID); e != nil {
		return "Invalid exchange-rate ID."
	}
	when, e := time.Parse(time.RFC3339, in.PurchasedAt)
	if e != nil {
		return "Enter a valid purchase date."
	}
	if in.DueDate != "" {
		d, e := time.Parse("2006-01-02", in.DueDate)
		if e != nil || d.Format("2006-01-02") < when.Format("2006-01-02") {
			return "Due date cannot precede the purchase date."
		}
	}
	if !currencyPattern.MatchString(in.Currency) || !decimal(in.Rate, 14, 10, true) {
		return "Select a currency and positive exchange rate (up to 10 decimal places)."
	}
	if in.Currency == "MMK" && (!sameNumber(in.Rate, "1") || in.RateID != "") {
		return "MMK uses a fixed rate of 1 without a foreign quote."
	}
	if len(in.Items) < 1 || len(in.Items) > 100 {
		return "Supply 1–100 purchase items."
	}
	for i := range in.Items {
		it := &in.Items[i]
		id, e := uuid(it.ProductID)
		if e != nil || !id.Valid {
			return "Invalid product ID."
		}
		if it.Discount == "" {
			it.Discount = "0"
		}
		if it.Tax == "" {
			it.Tax = "0"
		}
		if len(it.UnitCode) == 0 || len(it.UnitCode) > 20 || !decimal(it.Quantity, 14, 6, true) || !decimal(it.UnitsPerPack, 14, 6, true) || !decimal(it.UnitPrice, 14, 6, false) || !decimal(it.Discount, 16, 4, false) || !decimal(it.Tax, 16, 4, false) {
			return "Items require positive quantity/conversion and non-negative prices, discounts and taxes within their decimal limits."
		}
	}
	return ""
}
func audit(ctx context.Context, q *database.Queries, c *gin.Context, id pgtype.UUID, kind, action string, data []byte) error {
	actor, _ := authz.Principal(c)
	return q.RecordProductAudit(ctx, database.RecordProductAuditParams{ActorID: actor.ID, EntityID: id, EntityType: kind, Action: action, NewValue: data})
}
func (s *Service) Create(c *gin.Context) {
	var in Input
	if !decode(c, &in) {
		return
	}
	if msg := in.validate(); msg != "" {
		fail(c, 400, msg)
		return
	}
	data, _ := json.Marshal(in)
	h := sha256.Sum256(data)
	hash := hex.EncodeToString(h[:])
	requestID, _ := uuid(in.RequestID)
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	if e = q.LockPurchaseRequest(ctx, in.RequestID); e != nil {
		dbError(c, e)
		return
	}
	old, e := q.FindPurchaseRequest(ctx, requestID)
	if e == nil {
		if old.RequestHash.String != hash {
			fail(c, 409, "This request was already used with different purchase data.")
			return
		}
		v, e := q.GetPurchaseDocument(ctx, database.GetPurchaseDocumentParams{ID: old.ID, Costs: true})
		respond(c, v, e)
		return
	}
	if !errors.Is(e, pgx.ErrNoRows) {
		dbError(c, e)
		return
	}
	supplier, _ := uuid(in.SupplierID)
	if _, e = q.LockPurchaseSupplier(ctx, supplier); e != nil {
		fail(c, 400, "Choose an active supplier.")
		return
	}
	if _, e = q.LockPurchaseCurrency(ctx, in.Currency); e != nil {
		fail(c, 400, "Choose an active currency.")
		return
	}
	rateID, _ := uuid(in.RateID)
	if in.Currency != "MMK" {
		if rateID.Valid {
			r, err := q.GetPurchaseRate(ctx, rateID)
			when, _ := time.Parse(time.RFC3339, in.PurchasedAt)
			if err != nil || r.CurrencyCode != in.Currency || !sameNumber(r.Rate, in.Rate) || r.EffectiveAt.Time.After(when) {
				fail(c, 400, "The quote must match the currency, rate and purchase date.")
				return
			}
		} else {
			allowed, err := s.a.Allowed(c, permissions.ExchangeRatesManage)
			if err != nil {
				fail(c, 503, "Authorization unavailable.")
				return
			}
			if !allowed {
				fail(c, 403, "Custom rates require exchange_rates.manage. Select a saved historical quote.")
				return
			}
		}
	}
	actor, _ := authz.Principal(c)
	id, e := q.InsertPurchase(ctx, database.InsertPurchaseParams{ActorID: actor.ID, Data: data, RequestHash: pgtype.Text{String: hash, Valid: true}})
	if e != nil {
		dbError(c, e)
		return
	}
	for i, item := range in.Items {
		pid, _ := uuid(item.ProductID)
		pack, err := q.LockPurchasePackaging(ctx, database.LockPurchasePackagingParams{ID: pid, UnitCode: item.UnitCode})
		if err != nil {
			fail(c, 400, "Choose active products with valid packaging.")
			return
		}
		if !sameNumber(pack.UnitsPerPack, item.UnitsPerPack) {
			fail(c, 409, "Product packaging changed. Reload and review the conversion before posting.")
			return
		}
		itemData, _ := json.Marshal(item)
		e = q.InsertPurchaseItem(ctx, database.InsertPurchaseItemParams{PurchaseID: id, LineNumber: int32(i + 1), Data: itemData, ProductName: pgtype.Text{String: pack.Name, Valid: true}, Sku: pgtype.Text{String: pack.Sku, Valid: true}, UnitName: pgtype.Text{String: pack.UnitName, Valid: true}})
		if e != nil {
			dbError(c, e)
			return
		}
	}
	if e = q.PostPurchase(ctx, id); e != nil {
		dbError(c, e)
		return
	}
	after, e := q.GetPurchaseDocument(ctx, database.GetPurchaseDocumentParams{ID: id, Costs: true})
	if e != nil {
		dbError(c, e)
		return
	}
	if e = audit(ctx, q, c, id, "purchases", "purchases.create", after); e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(201, "application/json", after)
}
