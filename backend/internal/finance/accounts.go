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

func (s *Service) registerAccounts(r *gin.Engine, a *authz.Service) {
	r.GET("/api/v1/accounts/options", a.RequireAny(permissions.PaymentsManage, permissions.AccountsView, permissions.AccountsManage), s.AccountOptions)
	r.GET("/api/v1/accounts", a.Require(permissions.AccountsView), s.Accounts)
	r.POST("/api/v1/accounts", a.Require(permissions.AccountsManage), s.CreateAccount)
	r.PATCH("/api/v1/accounts/:id", a.Require(permissions.AccountsManage), s.UpdateAccount)
	r.GET("/api/v1/accounts/history", a.Require(permissions.AccountsView), s.AccountHistory)
	r.POST("/api/v1/accounts/entries", a.Require(permissions.AccountsManage), s.AccountEntry)
}
func (s *Service) UpdateAccount(c *gin.Context) {
	var in struct {
		Request   string `json:"request_id"`
		Account   string `json:"account_id"`
		Version   int    `json:"version"`
		Name      string `json:"name"`
		Bank      string `json:"bank"`
		Reference string `json:"reference"`
		Active    *bool  `json:"is_active"`
	}
	if !decode(c, &in) {
		return
	}
	in.Account = c.Param("id")
	in.Name = strings.TrimSpace(in.Name)
	if !id(in.Request) || !id(in.Account) || in.Version < 1 || in.Name == "" || len(in.Name) > 100 || len(in.Bank) > 100 || len(in.Reference) > 200 || in.Active == nil {
		fail(c, 400, "Enter valid account details and reload the latest version.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.MoneyAccountUpdate(c.Request.Context(), database.MoneyAccountUpdateParams{Data: d, Actor: actor.ID})
	})
}
func (s *Service) AccountOptions(c *gin.Context) {
	b, e := s.q.MoneyAccountOptions(c.Request.Context())
	respond(c, b, e)
}
func (s *Service) Accounts(c *gin.Context) {
	b, e := s.q.MoneyAccounts(c.Request.Context())
	respond(c, b, e)
}
func (s *Service) AccountHistory(c *gin.Context) {
	from, to, ok := dates(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	account, kind := c.Query("account_id"), c.Query("kind")
	if (account != "" && !id(account)) || len(kind) > 30 {
		fail(c, 400, "Invalid account filters.")
		return
	}
	b, e := s.q.AccountHistory(c.Request.Context(), database.AccountHistoryParams{AccountID: account, Kind: kind, StartOn: from, EndOn: to, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}
func (s *Service) CreateAccount(c *gin.Context) {
	var in struct {
		Request   string `json:"request_id"`
		Name      string `json:"name"`
		Bank      string `json:"bank"`
		Reference string `json:"reference"`
	}
	if !decode(c, &in) {
		return
	}
	if !id(in.Request) || strings.TrimSpace(in.Name) == "" || len(in.Name) > 100 || len(in.Bank) > 100 || len(in.Reference) > 200 {
		fail(c, 400, "Enter valid account details.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.MoneyAccountCreate(c.Request.Context(), database.MoneyAccountCreateParams{Data: d, Actor: actor.ID})
	})
}
func (s *Service) AccountEntry(c *gin.Context) {
	var in struct {
		Request     string `json:"request_id"`
		Account     string `json:"account_id"`
		Kind        string `json:"kind"`
		Amount      string `json:"amount_mmk"`
		Sender      string `json:"sender"`
		Description string `json:"description"`
		Date        string `json:"occurred_at"`
		Reverses    string `json:"reverses_id"`
	}
	if !decode(c, &in) {
		return
	}
	_, e := time.Parse(time.RFC3339, in.Date)
	if !id(in.Request) || !id(in.Account) || e != nil || len(in.Sender) > 200 || len(in.Description) > 1000 || (in.Kind != "REVERSAL" && !money.MatchString(in.Amount)) || (in.Kind == "REVERSAL" && !id(in.Reverses)) {
		fail(c, 400, "Enter valid account, date, amount and description.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.AccountEntryPost(c.Request.Context(), database.AccountEntryPostParams{Data: d, Actor: actor.ID})
	})
}
