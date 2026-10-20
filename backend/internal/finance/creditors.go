package finance

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"strings"
	"time"
)

func (s *Service) registerCreditors(r *gin.Engine, a *authz.Service) {
	r.POST("/api/v1/creditors/:id/transactions", a.Require(permissions.AccountsManage), s.PersonTransaction)
	r.POST("/api/v1/creditors/:id/repayments/:payment/reverse", a.Require(permissions.AccountsView), a.Require(permissions.PaymentsManage), a.Require(permissions.TransactionsReverse), s.ReverseCreditorRepayment)
	r.GET("/api/v1/creditors/options", a.RequireAny(permissions.PaymentsManage, permissions.AccountsView, permissions.AccountsManage), s.CreditorOptions)
	r.GET("/api/v1/creditors", a.Require(permissions.AccountsView), s.Creditors)
	r.POST("/api/v1/creditors", a.Require(permissions.AccountsManage), s.CreateCreditor)
	r.GET("/api/v1/creditors/:id/history", a.Require(permissions.AccountsView), s.CreditorHistory)
	r.POST("/api/v1/creditors/:id/repayments", a.Require(permissions.AccountsView), a.Require(permissions.PaymentsManage), s.RepayCreditor)
}
func (s *Service) CreditorOptions(c *gin.Context) {
	b, e := s.q.CreditorOptions(c.Request.Context())
	respond(c, b, e)
}
func (s *Service) Creditors(c *gin.Context) {
	b, e := s.q.Creditors(c.Request.Context())
	respond(c, b, e)
}
func (s *Service) CreateCreditor(c *gin.Context) {
	var in struct {
		Request string `json:"request_id"`
		Name    string `json:"name"`
		Contact string `json:"contact"`
	}
	if !decode(c, &in) {
		return
	}
	in.Name = strings.TrimSpace(in.Name)
	if !id(in.Request) || in.Name == "" || len(in.Name) > 100 || len(in.Contact) > 200 {
		fail(c, 400, "Enter a creditor name and valid contact details.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.CreditorCreate(c.Request.Context(), database.CreditorCreateParams{Data: d, Actor: actor.ID})
	})
}
func (s *Service) CreditorHistory(c *gin.Context) {
	v, e := uuid(c.Param("id"))
	if e != nil || !v.Valid {
		fail(c, 400, "Invalid creditor.")
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	b, e := s.q.CreditorHistory(c.Request.Context(), database.CreditorHistoryParams{CreditorID: v, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}
func (s *Service) RepayCreditor(c *gin.Context) {
	var in struct {
		Request   string `json:"request_id"`
		Creditor  string `json:"creditor_id"`
		Account   string `json:"account_id"`
		Amount    string `json:"amount_mmk"`
		Method    string `json:"method"`
		Date      string `json:"paid_at"`
		Reference string `json:"reference"`
		Notes     string `json:"notes"`
	}
	if !decode(c, &in) {
		return
	}
	in.Creditor = c.Param("id")
	_, e := time.Parse(time.RFC3339, in.Date)
	if !id(in.Request) || !id(in.Creditor) || !id(in.Account) || !money.MatchString(in.Amount) || e != nil || len(in.Reference) > 200 || len(in.Notes) > 1000 || (in.Method != "CASH" && in.Method != "BANK_TRANSFER" && in.Method != "MOBILE_PAYMENT" && in.Method != "OTHER") {
		fail(c, 400, "Enter a paying account, amount, method and valid date.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.CreditorRepay(c.Request.Context(), database.CreditorRepayParams{Data: d, Actor: actor.ID})
	})
}

func (s *Service) ReverseCreditorRepayment(c *gin.Context) {
	var in struct {
		Request  string `json:"request_id"`
		Creditor string `json:"creditor_id"`
		Payment  string `json:"payment_id"`
		Reason   string `json:"reason"`
	}
	if !decode(c, &in) {
		return
	}
	in.Creditor = c.Param("id")
	in.Payment = c.Param("payment")
	in.Reason = strings.TrimSpace(in.Reason)
	if !id(in.Request) || !id(in.Creditor) || !id(in.Payment) || in.Reason == "" || len(in.Reason) > 1000 {
		fail(c, 400, "Choose a repayment and enter a reversal reason.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.CreditorRepaymentReverse(c.Request.Context(), database.CreditorRepaymentReverseParams{Data: d, Actor: actor.ID})
	})
}

func (s *Service) PersonTransaction(c *gin.Context) {
	var in struct {
		Request     string `json:"request_id"`
		Creditor    string `json:"creditor_id"`
		Account     string `json:"account_id"`
		Kind        string `json:"kind"`
		Amount      string `json:"amount_mmk"`
		Date        string `json:"occurred_at"`
		Description string `json:"description"`
		Reference   string `json:"reference"`
		Reverses    string `json:"reverses_id"`
	}
	if !decode(c, &in) {
		return
	}
	in.Creditor = c.Param("id")
	_, e := time.Parse(time.RFC3339, in.Date)
	if !id(in.Request) || !id(in.Creditor) || !id(in.Account) || e != nil || !money.MatchString(in.Amount) || len(in.Description) > 1000 || len(in.Reference) > 200 {
		fail(c, 400, "Enter a person, account, amount, date and description.")
		return
	}
	if in.Kind == "REVERSAL" && !id(in.Reverses) {
		fail(c, 400, "Choose the original transaction.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.PersonTransaction(c.Request.Context(), database.PersonTransactionParams{Data: d, Actor: actor.ID})
	})
}
