package purchasing

import (
	"context"
	"encoding/json"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
)

func (s *Service) PaymentMethods(c *gin.Context) {
	v, e := s.q.SupplierPaymentMethods(c.Request.Context())
	respond(c, v, e)
}
func (s *Service) AddPaymentMethod(c *gin.Context) {
	var in struct {
		Code     string `json:"code"`
		Name     string `json:"name"`
		Category string `json:"category"`
	}
	if !decode(c, &in) {
		return
	}
	in.Name = strings.TrimSpace(in.Name)
	if !regexp.MustCompile(`^[A-Z][A-Z0-9_]{0,39}$`).MatchString(in.Code) || len(in.Name) == 0 || len(in.Name) > 100 || (in.Category != "CASH" && in.Category != "BANK_TRANSFER" && in.Category != "MOBILE_PAYMENT" && in.Category != "OTHER") {
		fail(c, 400, "Enter a unique method code, name and valid category.")
		return
	}
	ctx := c.Request.Context()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	e = q.AddSupplierPaymentMethod(ctx, database.AddSupplierPaymentMethodParams{Code: in.Code, Name: in.Name, Category: in.Category})
	if e == nil {
		actor, _ := authz.Principal(c)
		data, _ := json.Marshal(in)
		e = q.RecordProductAudit(ctx, database.RecordProductAuditParams{ActorID: actor.ID, EntityType: "supplier_payment_methods", Action: "supplier_payment_methods.create", NewValue: data})
	}
	if e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, in)
}
func (s *Service) PaymentPurchases(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	search, status := strings.TrimSpace(c.Query("q")), c.Query("payment_status")
	if len(search) > 200 || (status != "" && status != "UNPAID" && status != "PARTIALLY_PAID" && status != "PAID") {
		fail(c, 400, "Invalid payment filters.")
		return
	}
	v, e := s.q.SupplierPaymentPurchases(c.Request.Context(), database.SupplierPaymentPurchasesParams{Search: search, PaymentStatus: status, PageSize: size, PageOffset: offset})
	respond(c, v, e)
}
func (s *Service) PaymentHistory(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	v, e := s.q.SupplierPaymentHistory(c.Request.Context(), id)
	respond(c, v, e)
}
func (s *Service) RecordPayment(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	var in struct {
		RequestID  string `json:"request_id"`
		Amount     string `json:"amount"`
		MethodCode string `json:"method_code"`
		PaidAt     string `json:"paid_at"`
		Reference  string `json:"reference_number"`
		Bank       string `json:"bank_account"`
		Notes      string `json:"notes"`
	}
	if !decode(c, &in) {
		return
	}
	req, e := uuid(in.RequestID)
	_, dateErr := time.Parse(time.RFC3339, in.PaidAt)
	if e != nil || !req.Valid || dateErr != nil || !decimal(in.Amount, 16, 4, true) || len(in.MethodCode) > 40 || len(in.Reference) > 200 || len(in.Bank) > 200 || len(in.Notes) > 4000 {
		fail(c, 400, "Enter a positive payment amount, valid date, method and request ID. Reference and bank account allow 200 characters; notes allow 4000.")
		return
	}
	data, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	_, e = s.q.WithTx(tx).RecordSupplierPayment(ctx, database.RecordSupplierPaymentParams{PurchaseID: id, Actor: actor.ID, Data: data})
	if e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		var pe *pgconn.PgError
		if errors.As(e, &pe) && pe.Code == "23514" {
			fail(c, 409, pe.Message)
			return
		}
		dbError(c, e)
		return
	}
	v, e := s.q.SupplierPaymentHistory(ctx, id)
	respond(c, v, e)
}
