package receiving

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"regexp"
	"time"
)

func (s *Service) ManualProducts(c *gin.Context) {
	search := c.Query("q")
	if len(search) > 200 {
		fail(c, 400, "Search is too long.")
		return
	}
	b, e := s.q.ManualStockProducts(c.Request.Context(), search)
	response(c, b, e)
}
func (s *Service) ManualStock(c *gin.Context) {
	var in struct {
		Request   string `json:"request_id"`
		Version   string `json:"version"`
		Product   string `json:"product_id"`
		Warehouse string `json:"warehouse_id"`
		Unit      string `json:"unit_code"`
		Quantity  string `json:"quantity"`
		Cost      string `json:"unit_cost_mmk"`
		Retail    string `json:"retail_price_mmk"`
		Wholesale string `json:"wholesale_price_mmk"`
		Date      string `json:"received_at"`
		Expiry    string `json:"expires_on"`
		Reason    string `json:"reason"`
	}
	if !decode(c, &in) {
		return
	}
	for _, v := range []string{in.Request, in.Product, in.Warehouse} {
		u, e := uuid(v)
		if e != nil || !u.Valid {
			fail(c, 400, "Invalid reference.")
			return
		}
	}
	_, e := time.Parse(time.RFC3339, in.Date)
	money := regexp.MustCompile(`^[0-9]{1,14}(\.[0-9]{1,4})?$`)
	if e != nil || !regexp.MustCompile(`^[0-9]{1,14}(\.[0-9]{1,6})?$`).MatchString(in.Quantity) || !money.MatchString(in.Cost) || !money.MatchString(in.Retail) || !money.MatchString(in.Wholesale) || len(in.Unit) > 20 || len(in.Reason) > 2000 {
		fail(c, 400, "Enter valid quantities, prices, cost and date.")
		return
	}
	if in.Expiry != "" {
		if _, e = time.Parse("2006-01-02", in.Expiry); e != nil {
			fail(c, 400, "Invalid expiry date.")
			return
		}
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	ctx := c.Request.Context()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	result, e := s.q.WithTx(tx).ManualStockPost(ctx, database.ManualStockPostParams{Data: d, Actor: actor.ID})
	if e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": result})
}
