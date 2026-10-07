package pos

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

func (s *Service) registerPricing(r *gin.Engine, a *authz.Service) {
	r.GET("/api/v1/pos/pricing-costs", a.Require(permissions.ProductsUpdate), a.Require(permissions.FinanceViewLandedCost), a.Require(permissions.PurchasesViewCost), s.PricingCosts)
	r.PUT("/api/v1/pos/landed-prices", a.Require(permissions.ProductsUpdate), a.Require(permissions.FinanceViewLandedCost), a.Require(permissions.PurchasesViewCost), s.LandedPrices)
}
func (s *Service) PricingCosts(c *gin.Context) {
	p, e := uuid(c.Query("product_id"))
	w, e2 := uuid(c.Query("warehouse_id"))
	if e != nil || e2 != nil || !p.Valid || !w.Valid {
		fail(c, 400, "Choose a product and warehouse.")
		return
	}
	b, e := s.q.WarehousePricingCosts(c.Request.Context(), database.WarehousePricingCostsParams{ProductID: p, WarehouseID: w})
	respond(c, b, e)
}
func (s *Service) LandedPrices(c *gin.Context) {
	var in struct {
		Warehouse string `json:"warehouse_id"`
		Product   string `json:"product_id"`
		Source    string `json:"shipment_item_id"`
		Unit      string `json:"unit_code"`
		Version   string `json:"version"`
		Mode      string `json:"mode"`
		Retail    string `json:"retail_value"`
		Wholesale string `json:"wholesale_value"`
	}
	if !decode(c, &in) {
		return
	}
	if !id(in.Warehouse) || !id(in.Product) || !id(in.Source) || in.Unit == "" || len(in.Unit) > 20 || in.Version == "" || len(in.Version) > 20 || (in.Mode != "PER_UNIT" && in.Mode != "MARKUP") || !money.MatchString(in.Retail) || !money.MatchString(in.Wholesale) {
		fail(c, 400, "Enter valid pricing details.")
		return
	}
	d, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	ctx := c.Request.Context()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(ctx)
	e = s.q.WithTx(tx).LandedWarehousePricesSave(ctx, database.LandedWarehousePricesSaveParams{Data: d, Actor: actor.ID})
	if e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.Status(204)
}
