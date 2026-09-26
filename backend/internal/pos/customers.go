package pos

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"strings"
)

func (s *Service) registerCustomers(r *gin.Engine, a *authz.Service) {
	r.GET("/api/v1/customer-catalog", a.Require(permissions.CustomersManage), s.CustomerCatalog)
	r.GET("/api/v1/customers", a.Require(permissions.CustomersManage), s.CustomersList)
	r.POST("/api/v1/customers", a.Require(permissions.CustomersManage), s.CustomerSave)
	r.PUT("/api/v1/customers/:id", a.Require(permissions.CustomersManage), s.CustomerSave)
	r.GET("/api/v1/customers/:id", a.Require(permissions.CustomersManage), s.CustomerDetail)
	r.GET("/api/v1/customers/:id/history", a.Require(permissions.CustomersManage), s.CustomerHistory)
	r.GET("/api/v1/customers/:id/payments", a.Require(permissions.CustomersManage), s.CustomerPayments)
	r.POST("/api/v1/customers/:id/payments", a.Require(permissions.CustomersManage), a.Require(permissions.PaymentsManage), s.CustomerPayment)
	r.GET("/api/v1/customers/:id/prices", a.RequireAny(permissions.CustomersManage, permissions.SalesCreate), s.CustomerPrices)
	r.PUT("/api/v1/customers/:id/prices", a.Require(permissions.CustomersManage), s.CustomerPrice)
}
func (s *Service) CustomersList(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	kind, status := c.Query("type"), c.Query("status")
	if (kind != "" && kind != "RETAIL" && kind != "WHOLESALE") || (status != "" && status != "ACTIVE" && status != "INACTIVE") {
		fail(c, 400, "Invalid customer filter.")
		return
	}
	b, e := s.q.CustomersList(c.Request.Context(), database.CustomersListParams{Search: q, Kind: kind, Status: status, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}
func (s *Service) CustomerDetail(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.CustomerDetail(c.Request.Context(), v)
	respond(c, b, e)
}
func (s *Service) CustomerPrices(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.CustomerPrices(c.Request.Context(), v)
	respond(c, b, e)
}
func (s *Service) CustomerPayments(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.CustomerPayments(c.Request.Context(), v)
	respond(c, b, e)
}
func (s *Service) CustomerHistory(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	b, e := s.q.CustomerHistory(c.Request.Context(), database.CustomerHistoryParams{ID: v, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}
func (s *Service) CustomerSave(c *gin.Context) {
	var in struct {
		ID       string `json:"id"`
		Version  string `json:"version"`
		Code     string `json:"code"`
		Name     string `json:"name"`
		Business string `json:"business_name"`
		Phone    string `json:"phone"`
		Address  string `json:"address"`
		Kind     string `json:"customer_type"`
		Limit    string `json:"credit_limit_mmk"`
		Notes    string `json:"notes"`
		Active   bool   `json:"is_active"`
	}
	if !decode(c, &in) {
		return
	}
	in.ID = c.Param("id")
	in.Name = strings.TrimSpace(in.Name)
	in.Code = strings.TrimSpace(in.Code)
	if (in.ID != "" && (!id(in.ID) || in.Version == "")) || len(in.Version) > 20 || in.Name == "" || len(in.Name) > 150 || in.Code == "" || len(in.Code) > 100 || len(in.Business) > 200 || len(in.Phone) > 100 || len(in.Address) > 2000 || len(in.Notes) > 4000 || (in.Kind != "RETAIL" && in.Kind != "WHOLESALE") || !money.MatchString(in.Limit) {
		fail(c, 400, "Enter valid customer details and credit limit.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	v, e := s.q.CustomerSave(c.Request.Context(), database.CustomerSaveParams{Data: d, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(200, gin.H{"id": v})
}
func (s *Service) CustomerPrice(c *gin.Context) {
	var in struct {
		Customer string `json:"customer_id"`
		Version  string `json:"version"`
		Product  string `json:"product_id"`
		Unit     string `json:"unit_code"`
		Price    string `json:"price_mmk"`
		Remove   bool   `json:"remove"`
	}
	if !decode(c, &in) {
		return
	}
	in.Customer = c.Param("id")
	if !id(in.Customer) || !id(in.Product) || in.Version == "" || len(in.Version) > 20 || in.Unit == "" || len(in.Unit) > 20 || !money.MatchString(in.Price) {
		fail(c, 400, "Choose a product, unit and valid special price.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	e := s.q.CustomerPrice(c.Request.Context(), database.CustomerPriceParams{Data: d, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	c.Status(204)
}
func (s *Service) CustomerPayment(c *gin.Context) {
	var in struct {
		Customer  string `json:"customer_id"`
		Request   string `json:"request_id"`
		Sale      string `json:"sale_id"`
		Amount    string `json:"amount_mmk"`
		Method    string `json:"method"`
		Reference string `json:"reference"`
	}
	if !decode(c, &in) {
		return
	}
	in.Customer = c.Param("id")
	if !id(in.Customer) || !id(in.Request) || !id(in.Sale) || !money.MatchString(in.Amount) || len(in.Reference) > 200 || !paymentMethod(in.Method) {
		fail(c, 400, "Enter valid payment details.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	v, e := s.q.CustomerPayment(c.Request.Context(), database.CustomerPaymentParams{Data: d, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": v})
}
func paymentMethod(v string) bool {
	return v == "CASH" || v == "BANK_TRANSFER" || v == "MOBILE_PAYMENT" || v == "OTHER"
}

func (s *Service) CustomerCatalog(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	b, e := s.q.CustomerCatalog(c.Request.Context(), q)
	respond(c, b, e)
}
