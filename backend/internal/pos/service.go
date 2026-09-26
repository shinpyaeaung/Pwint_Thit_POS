package pos

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
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
	s.registerCustomers(r, a)
	r.GET("/api/v1/pos/products", a.RequireAny(permissions.SalesCreate, permissions.ProductsUpdate), s.Products)
	r.GET("/api/v1/pos/warehouses", a.RequireAny(permissions.SalesCreate, permissions.ProductsUpdate), s.Warehouses)
	r.GET("/api/v1/pos/customers", a.RequireAny(permissions.SalesCreate, permissions.CustomersManage), s.Customers)
	r.POST("/api/v1/pos/customers", a.Require(permissions.CustomersManage), s.CreateCustomer)
	r.PUT("/api/v1/pos/prices", a.Require(permissions.ProductsUpdate), s.Prices)
	r.POST("/api/v1/pos/quote", a.Require(permissions.SalesCreate), s.Checkout(true))
	r.POST("/api/v1/pos/checkout", a.Require(permissions.SalesCreate), a.Require(permissions.PaymentsManage), s.Checkout(false))
	r.GET("/api/v1/sales", a.Require(permissions.SalesView), s.Sales)
	r.GET("/api/v1/sales/:id", a.RequireAny(permissions.SalesView, permissions.SalesCreate), s.Invoice)
}
func respond(c *gin.Context, b []byte, e error) {
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", b)
}
func search(c *gin.Context) (string, bool) {
	q := c.Query("q")
	if len(q) > 200 {
		fail(c, 400, "Search is too long.")
		return "", false
	}
	return q, true
}
func (s *Service) Products(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	w, e := uuid(c.Query("warehouse_id"))
	if e != nil || !w.Valid {
		fail(c, 400, "Choose a warehouse.")
		return
	}
	b, e := s.q.POSProducts(c.Request.Context(), database.POSProductsParams{Search: q, WarehouseID: w})
	respond(c, b, e)
}
func (s *Service) Warehouses(c *gin.Context) {
	b, e := s.q.POSWarehouses(c.Request.Context())
	respond(c, b, e)
}
func (s *Service) Customers(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	b, e := s.q.POSCustomers(c.Request.Context(), q)
	respond(c, b, e)
}

var money = regexp.MustCompile(`^[0-9]{1,14}(\.[0-9]{1,4})?$`)
var quantity = regexp.MustCompile(`^[0-9]{1,14}(\.[0-9]{1,6})?$`)

func id(v string) bool { u, e := uuid(v); return e == nil && u.Valid }
func (s *Service) CreateCustomer(c *gin.Context) {
	var in struct {
		Name  string `json:"name"`
		Phone string `json:"phone"`
		Type  string `json:"customer_type"`
		Limit string `json:"credit_limit_mmk"`
	}
	if !decode(c, &in) {
		return
	}
	in.Name = strings.TrimSpace(in.Name)
	if in.Name == "" || len(in.Name) > 150 || len(in.Phone) > 100 || (in.Type != "RETAIL" && in.Type != "WHOLESALE") || !money.MatchString(in.Limit) {
		fail(c, 400, "Enter a customer name, type and valid credit limit.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	v, e := s.q.POSCreateCustomer(c.Request.Context(), database.POSCreateCustomerParams{Data: d, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": v})
}
func (s *Service) Prices(c *gin.Context) {
	var in struct {
		Product   string `json:"product_id"`
		Unit      string `json:"unit_code"`
		Version   string `json:"version"`
		Retail    string `json:"retail_price_mmk"`
		Wholesale string `json:"wholesale_price_mmk"`
	}
	if !decode(c, &in) {
		return
	}
	if !id(in.Product) || len(in.Unit) > 20 || in.Unit == "" || len(in.Version) > 20 || in.Version == "" || !money.MatchString(in.Retail) || !money.MatchString(in.Wholesale) {
		fail(c, 400, "Enter valid retail and wholesale prices.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	if e := s.q.POSPrices(c.Request.Context(), database.POSPricesParams{Data: d, Actor: actor.ID}); e != nil {
		dbError(c, e)
		return
	}
	c.Status(204)
}

type Line struct {
	Product  string `json:"product_id"`
	Unit     string `json:"unit_code"`
	Pack     string `json:"units_per_pack"`
	Quantity string `json:"quantity"`
	Price    string `json:"unit_price_mmk"`
	Discount string `json:"discount_mmk"`
}
type Checkout struct {
	ApproveBelowCost bool   `json:"approve_below_cost"`
	Request          string `json:"request_id"`
	Warehouse        string `json:"warehouse_id"`
	Customer         string `json:"customer_id"`
	Mode             string `json:"pricing_mode"`
	Tender           string `json:"tender_mmk"`
	Method           string `json:"payment_method"`
	Reference        string `json:"payment_reference"`
	Due              string `json:"due_date"`
	Reason           string `json:"reason"`
	Quote            string `json:"quote_hash"`
	Items            []Line `json:"items"`
}

func (s *Service) allowed(c *gin.Context, p permissions.Code) (bool, bool) {
	v, e := s.a.Allowed(c, p)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return false, false
	}
	return v, true
}
func (s *Service) Checkout(preview bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		var in Checkout
		if !decode(c, &in) {
			return
		}
		if !id(in.Request) || !id(in.Warehouse) || (in.Customer != "" && !id(in.Customer)) || (in.Mode != "RETAIL" && in.Mode != "WHOLESALE") || !money.MatchString(in.Tender) || len(in.Reference) > 200 || len(in.Reason) > 2000 || len(in.Quote) > 100 || len(in.Items) < 1 || len(in.Items) > 100 {
			fail(c, 400, "Enter valid checkout details.")
			return
		}
		switch in.Method {
		case "CASH", "BANK_TRANSFER", "MOBILE_PAYMENT", "OTHER":
		default:
			fail(c, 400, "Choose a payment method.")
			return
		}
		if in.Due != "" {
			if _, e := time.Parse("2006-01-02", in.Due); e != nil {
				fail(c, 400, "Invalid due date.")
				return
			}
		}
		for _, l := range in.Items {
			if !id(l.Product) || l.Unit == "" || len(l.Unit) > 20 || !quantity.MatchString(l.Pack) || !quantity.MatchString(l.Quantity) || !money.MatchString(l.Price) || !money.MatchString(l.Discount) {
				fail(c, 400, "Enter valid quantities, prices and discounts.")
				return
			}
		}
		discount, ok := s.allowed(c, permissions.SalesDiscount)
		if !ok {
			return
		}
		below, ok := s.allowed(c, permissions.SalesBelowCost)
		if !ok {
			return
		}
		costs, ok := s.allowed(c, permissions.FinanceViewLandedCost)
		if !ok {
			return
		}
		profit, ok := s.allowed(c, permissions.FinanceViewProfit)
		if !ok {
			return
		}
		d, _ := json.Marshal(in)
		actor, _ := authz.Principal(c)
		params := database.POSCheckoutParams{Data: d, Actor: actor.ID, Discounts: discount, BelowCost: below, Preview: preview, Costs: costs, Profits: profit}
		b, e := s.checkout(c.Request.Context(), params)
		if e != nil {
			dbError(c, e)
			return
		}
		status := 201
		if preview {
			status = 200
		}
		c.Data(status, "application/json", b)
	}
}
func (s *Service) Invoice(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	all, ok := s.allowed(c, permissions.SalesView)
	if !ok {
		return
	}
	costs, ok := s.allowed(c, permissions.FinanceViewLandedCost)
	if !ok {
		return
	}
	profits, ok := s.allowed(c, permissions.FinanceViewProfit)
	if !ok {
		return
	}
	actor, _ := authz.Principal(c)
	b, e := s.q.POSInvoice(c.Request.Context(), database.POSInvoiceParams{ID: v, Actor: actor.ID, AllSales: all, Costs: costs, Profits: profits})
	respond(c, b, e)
}
func (s *Service) Sales(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	b, e := s.q.POSSales(c.Request.Context(), database.POSSalesParams{Search: q, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}

// Posting has one explicit transaction boundary, including all function and trigger
// writes. Never send success until COMMIT succeeds. A lost commit response is safe
// to retry using the same request UUID and payload.
func (s *Service) checkout(ctx context.Context, params database.POSCheckoutParams) ([]byte, error) {
	if params.Preview {
		return s.q.POSCheckout(ctx, params)
	}
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(cleanup)
	}()
	result, err := s.q.WithTx(tx).POSCheckout(ctx, params)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return result, nil
}
