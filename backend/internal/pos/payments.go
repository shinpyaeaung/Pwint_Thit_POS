package pos

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"time"
)

func (s *Service) registerPayments(r *gin.Engine, a *authz.Service) {
	r.GET("/api/v1/customer-payments", a.Require(permissions.CustomersManage), s.CentralCustomers)
	r.GET("/api/v1/transport-payments", a.Require(permissions.ShipmentsView), a.Require(permissions.ShipmentsViewCost), s.TransportPayments)
	r.GET("/api/v1/transport-payments/:id", a.Require(permissions.ShipmentsView), a.Require(permissions.ShipmentsViewCost), s.TransportHistory)
	r.POST("/api/v1/transport-payments", a.Require(permissions.ShipmentsView), a.Require(permissions.ShipmentsViewCost), a.Require(permissions.PaymentsManage), s.TransportPay)
}
func (s *Service) CentralCustomers(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	status := c.Query("status")
	if status != "" && status != "PAID" && status != "UNPAID" && status != "PARTIALLY_PAID" && status != "OVERDUE" {
		fail(c, 400, "Invalid payment status.")
		return
	}
	b, e := s.q.CustomerPaymentList(c.Request.Context(), database.CustomerPaymentListParams{Search: q, Status: status, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}
func (s *Service) TransportPayments(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	status := c.Query("status")
	if status != "" && status != "PAID" && status != "UNPAID" && status != "PARTIALLY_PAID" {
		fail(c, 400, "Invalid payment status.")
		return
	}
	b, e := s.q.TransportPaymentList(c.Request.Context(), database.TransportPaymentListParams{Search: q, Status: status, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}
func (s *Service) TransportHistory(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.TransportPaymentHistory(c.Request.Context(), v)
	respond(c, b, e)
}
func (s *Service) TransportPay(c *gin.Context) {
	var in struct {
		Request   string `json:"request_id"`
		Target    string `json:"target_id"`
		Kind      string `json:"kind"`
		Amount    string `json:"amount"`
		Method    string `json:"method_code"`
		Date      string `json:"paid_at"`
		Reference string `json:"reference_number"`
		Bank      string `json:"bank_account"`
		Notes     string `json:"notes"`
	}
	if !decode(c, &in) {
		return
	}
	_, dateErr := time.Parse(time.RFC3339, in.Date)
	if !id(in.Request) || !id(in.Target) || (in.Kind != "TRANSPORT" && in.Kind != "ADDITIONAL_COST") || !money.MatchString(in.Amount) || dateErr != nil || len(in.Method) > 40 || len(in.Reference) > 200 || len(in.Bank) > 200 || len(in.Notes) > 4000 {
		fail(c, 400, "Enter valid payment details.")
		return
	}
	data, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	ctx := c.Request.Context()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	result, e := s.q.WithTx(tx).TransportPaymentPost(ctx, database.TransportPaymentPostParams{Data: data, Actor: actor.ID})
	if e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": result})
}
