package pos

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"strings"
	"time"
)

func (s *Service) registerReturns(r *gin.Engine, a *authz.Service) {
	r.GET("/api/v1/stock-issues/choices", a.Require(permissions.DamageManage), s.StockChoices)
	r.GET("/api/v1/stock-issues", a.Require(permissions.DamageManage), s.StockHistory)
	r.POST("/api/v1/stock-issues", a.Require(permissions.DamageManage), s.StockIssue)
	r.GET("/api/v1/returns", a.Require(permissions.ReturnsManage), s.ReturnHistory)
	r.GET("/api/v1/returns/sales", a.Require(permissions.ReturnsManage), s.ReturnSaleChoices)
	r.GET("/api/v1/returns/sales/:id", a.Require(permissions.ReturnsManage), s.ReturnSaleSource)
	r.POST("/api/v1/returns/sales", a.Require(permissions.ReturnsManage), s.ReturnPost(false, false))
	r.POST("/api/v1/returns/sales/preview", a.Require(permissions.ReturnsManage), s.ReturnPost(false, true))
	r.GET("/api/v1/returns/purchases", a.Require(permissions.ReturnsManage), a.Require(permissions.PurchasesViewCost), s.ReturnPurchaseChoices)
	r.GET("/api/v1/returns/purchases/:id", a.Require(permissions.ReturnsManage), a.Require(permissions.PurchasesViewCost), s.ReturnPurchaseSource)
	r.POST("/api/v1/returns/purchases", a.Require(permissions.ReturnsManage), a.Require(permissions.PurchasesViewCost), s.ReturnPost(true, false))
	r.POST("/api/v1/returns/purchases/preview", a.Require(permissions.ReturnsManage), a.Require(permissions.PurchasesViewCost), s.ReturnPost(true, true))
}
func (s *Service) StockChoices(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	b, e := s.q.StockIssueChoices(c.Request.Context(), q)
	respond(c, b, e)
}
func (s *Service) StockHistory(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	costs, ok := s.allowed(c, permissions.FinanceViewLandedCost)
	if !ok {
		return
	}
	b, e := s.q.StockIssuesHistory(c.Request.Context(), database.StockIssuesHistoryParams{Search: q, PageSize: size, PageOffset: offset, Costs: costs})
	respond(c, b, e)
}
func (s *Service) ReturnHistory(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	costs, ok := s.allowed(c, permissions.PurchasesViewCost)
	if !ok {
		return
	}
	b, e := s.q.ReturnsHistory(c.Request.Context(), database.ReturnsHistoryParams{PageSize: size, PageOffset: offset, PurchaseCosts: costs})
	respond(c, b, e)
}
func (s *Service) ReturnSaleChoices(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	b, e := s.q.ReturnSaleChoices(c.Request.Context(), q)
	respond(c, b, e)
}
func (s *Service) ReturnPurchaseChoices(c *gin.Context) {
	q, ok := search(c)
	if !ok {
		return
	}
	b, e := s.q.ReturnPurchaseChoices(c.Request.Context(), q)
	respond(c, b, e)
}
func (s *Service) ReturnSaleSource(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.ReturnSaleSource(c.Request.Context(), v)
	respond(c, b, e)
}
func (s *Service) ReturnPurchaseSource(c *gin.Context) {
	v, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.ReturnPurchaseSource(c.Request.Context(), v)
	respond(c, b, e)
}
func (s *Service) StockIssue(c *gin.Context) {
	var in struct {
		Request   string `json:"request_id"`
		Batch     string `json:"batch_id"`
		Warehouse string `json:"warehouse_id"`
		Version   string `json:"version"`
		Kind      string `json:"kind"`
		Bucket    string `json:"bucket"`
		Quantity  string `json:"quantity"`
		Reason    string `json:"reason"`
		Notes     string `json:"notes"`
	}
	if !decode(c, &in) {
		return
	}
	in.Reason = strings.TrimSpace(in.Reason)
	if !id(in.Request) || !id(in.Batch) || !id(in.Warehouse) || in.Version == "" || len(in.Version) > 20 || !quantity.MatchString(in.Quantity) || in.Reason == "" || len(in.Reason) > 2000 || len(in.Notes) > 4000 || (in.Kind != "DAMAGE" && in.Kind != "MISSING" && in.Kind != "DISCARD") || (in.Bucket != "SELLABLE" && in.Bucket != "DAMAGED") {
		fail(c, 400, "Choose stock, quantity, disposition and a reason.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	b, e := s.q.StockIssue(c.Request.Context(), database.StockIssueParams{Data: d, Actor: actor.ID})
	respond(c, b, e)
}

type ReturnLine struct {
	SaleBatch   string `json:"sale_item_batch_id"`
	Batch       string `json:"batch_id"`
	Quantity    string `json:"quantity"`
	Disposition string `json:"disposition"`
	Bucket      string `json:"bucket"`
}
type ReturnInput struct {
	Quote       string       `json:"quote_hash"`
	Request     string       `json:"request_id"`
	Sale        string       `json:"sale_id"`
	Purchase    string       `json:"purchase_id"`
	Replacement string       `json:"replacement_sale_id"`
	Warehouse   string       `json:"warehouse_id"`
	Resolution  string       `json:"resolution"`
	Reason      string       `json:"reason"`
	Method      string       `json:"method"`
	Reference   string       `json:"reference"`
	Approved    bool         `json:"approve_refund"`
	Items       []ReturnLine `json:"items"`
}

func (s *Service) ReturnPost(purchase, preview bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		var in ReturnInput
		if !decode(c, &in) {
			return
		}
		in.Reason = strings.TrimSpace(in.Reason)
		if !id(in.Request) || in.Reason == "" || len(in.Reason) > 2000 || len(in.Reference) > 200 || !paymentMethod(in.Method) || len(in.Items) < 1 || len(in.Items) > 100 {
			fail(c, 400, "Enter valid return details and a reason.")
			return
		}
		if purchase {
			if !id(in.Purchase) || !id(in.Warehouse) || (in.Resolution != "REFUND" && in.Resolution != "SUPPLIER_CREDIT") {
				fail(c, 400, "Choose a purchase, warehouse and resolution.")
				return
			}
		} else {
			if !id(in.Sale) || (in.Resolution != "REFUND" && in.Resolution != "CREDIT" && in.Resolution != "EXCHANGE") || (in.Replacement != "" && !id(in.Replacement)) {
				fail(c, 400, "Choose an invoice and return resolution.")
				return
			}
		}
		seen := map[string]bool{}
		for _, l := range in.Items {
			key := l.SaleBatch
			if purchase {
				key = l.Batch
			}
			if !id(key) || seen[key] || !quantity.MatchString(l.Quantity) || (!purchase && l.Disposition != "SELLABLE" && l.Disposition != "DAMAGED" && l.Disposition != "DISCARD") || (purchase && l.Bucket != "SELLABLE" && l.Bucket != "DAMAGED") {
				fail(c, 400, "Enter each return batch once with a valid quantity and disposition.")
				return
			}
			seen[key] = true
		}
		if in.Resolution == "REFUND" || in.Resolution == "EXCHANGE" {
			for _, p := range []permissions.Code{permissions.RefundsApprove, permissions.PaymentsManage} {
				allowed, ok := s.allowed(c, p)
				if !ok {
					return
				}
				if !allowed {
					fail(c, 403, "Refund approval and payment permissions are required.")
					return
				}
			}
			if !preview && !in.Approved {
				fail(c, 400, "Explicitly approve the refund before posting.")
				return
			}
		}
		d, _ := json.Marshal(in)
		actor, _ := authz.Principal(c)
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
		q := s.q.WithTx(tx)
		var b []byte
		if purchase {
			b, e = q.PurchaseReturnPost(c.Request.Context(), database.PurchaseReturnPostParams{Data: d, Actor: actor.ID})
		} else {
			b, e = q.SalesReturnPost(c.Request.Context(), database.SalesReturnPostParams{Data: d, Actor: actor.ID})
		}
		if e != nil {
			dbError(c, e)
			return
		}
		var result map[string]any
		if e = json.Unmarshal(b, &result); e != nil {
			dbError(c, e)
			return
		}
		recordID := result["id"]
		delete(result, "id")
		canonical, _ := json.Marshal(result)
		hash := sha256.Sum256(canonical)
		quote := hex.EncodeToString(hash[:])
		if preview {
			if e = tx.Rollback(c.Request.Context()); e != nil {
				dbError(c, e)
				return
			}
			result["quote_hash"] = quote
			c.JSON(200, result)
			return
		}
		if in.Quote != quote {
			fail(c, 409, "Return amounts changed. Review the return again.")
			return
		}
		if e = tx.Commit(c.Request.Context()); e != nil {
			dbError(c, e)
			return
		}
		result["id"] = recordID
		c.JSON(200, result)
	}
}
