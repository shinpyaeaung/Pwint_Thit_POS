package finance

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
	r.GET("/api/v1/expenses/categories", a.Require(permissions.ExpensesManage), s.Categories)
	r.GET("/api/v1/expenses", a.Require(permissions.ExpensesManage), s.List)
	r.POST("/api/v1/expenses", a.Require(permissions.ExpensesManage), s.Post)
	r.POST("/api/v1/expenses/:id/reverse", a.Require(permissions.ExpensesManage), a.Require(permissions.TransactionsReverse), a.Require(permissions.PaymentsManage), s.Reverse)
	r.GET("/api/v1/finance/profit", a.Require(permissions.FinanceViewProfit), s.Profit)
}
func respond(c *gin.Context, b []byte, e error) {
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", b)
}
func dates(c *gin.Context) (string, string, bool) {
	from, to := c.Query("from"), c.Query("to")
	var f, t time.Time
	var e error
	if from != "" {
		f, e = time.Parse("2006-01-02", from)
		if e != nil {
			fail(c, 400, "Invalid start date.")
			return "", "", false
		}
	}
	if to != "" {
		t, e = time.Parse("2006-01-02", to)
		if e != nil {
			fail(c, 400, "Invalid end date.")
			return "", "", false
		}
	}
	if from != "" && to != "" && (t.Before(f) || t.Sub(f) > 3660*24*time.Hour) {
		fail(c, 400, "Choose an ordered date range of up to ten years.")
		return "", "", false
	}
	return from, to, true
}
func (s *Service) Categories(c *gin.Context) {
	b, e := s.q.ExpenseCategories(c.Request.Context())
	respond(c, b, e)
}
func (s *Service) List(c *gin.Context) {
	from, to, ok := dates(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	q := c.Query("q")
	if len(q) > 200 {
		fail(c, 400, "Search is too long.")
		return
	}
	b, e := s.q.ExpensesList(c.Request.Context(), database.ExpensesListParams{StartOn: from, EndOn: to, Search: q, PageSize: size, PageOffset: offset})
	respond(c, b, e)
}
func (s *Service) Profit(c *gin.Context) {
	from, to, ok := dates(c)
	if !ok {
		return
	}
	b, e := s.q.ProfitReport(c.Request.Context(), database.ProfitReportParams{StartOn: from, EndOn: to})
	respond(c, b, e)
}

var money = regexp.MustCompile(`^[0-9]{1,14}(\.[0-9]{1,4})?$`)

func id(v string) bool { u, e := uuid(v); return e == nil && u.Valid }
func (s *Service) write(c *gin.Context, action func(*database.Queries) (any, error)) {
	tx, e := s.db.Begin(c.Request.Context())
	if e != nil {
		dbError(c, e)
		return
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(ctx)
	}()
	result, e := action(s.q.WithTx(tx))
	if e != nil {
		dbError(c, e)
		return
	}
	if e = tx.Commit(c.Request.Context()); e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": result})
}
func (s *Service) Post(c *gin.Context) {
	var in struct {
		Request     string `json:"request_id"`
		Category    string `json:"category_id"`
		Description string `json:"description"`
		Date        string `json:"incurred_on"`
		Amount      string `json:"amount_mmk"`
		Notes       string `json:"notes"`
		Paid        bool   `json:"paid_now"`
		Method      string `json:"method"`
		Reference   string `json:"reference"`
	}
	if !decode(c, &in) {
		return
	}
	in.Description = strings.TrimSpace(in.Description)
	_, e := time.Parse("2006-01-02", in.Date)
	if !id(in.Request) || !id(in.Category) || in.Description == "" || len(in.Description) > 500 || e != nil || !money.MatchString(in.Amount) || len(in.Notes) > 4000 || len(in.Reference) > 200 || (in.Method != "CASH" && in.Method != "BANK_TRANSFER" && in.Method != "MOBILE_PAYMENT" && in.Method != "OTHER") {
		fail(c, 400, "Enter a category, description, date and valid amount.")
		return
	}
	if in.Paid {
		allowed, e := s.a.Allowed(c, permissions.PaymentsManage)
		if e != nil {
			fail(c, 503, "Authorization unavailable.")
			return
		}
		if !allowed {
			fail(c, 403, "Payment permission is required to record a paid expense.")
			return
		}
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.ExpensePost(c.Request.Context(), database.ExpensePostParams{Data: d, Actor: actor.ID})
	})
}
func (s *Service) Reverse(c *gin.Context) {
	var in struct {
		Request string `json:"request_id"`
		Expense string `json:"expense_id"`
		Reason  string `json:"reason"`
	}
	if !decode(c, &in) {
		return
	}
	in.Expense = c.Param("id")
	in.Reason = strings.TrimSpace(in.Reason)
	if !id(in.Request) || !id(in.Expense) || in.Reason == "" || len(in.Reason) > 2000 {
		fail(c, 400, "Enter a reversal reason.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	s.write(c, func(q *database.Queries) (any, error) {
		return q.ExpenseReverse(c.Request.Context(), database.ExpenseReverseParams{Data: d, Actor: actor.ID})
	})
}
