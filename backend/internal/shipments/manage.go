package shipments

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
)

func (s *Service) Edit(c *gin.Context) {
	var in struct {
		Fulfillment *Fulfillment `json:"fulfillment,omitempty"`
		Version     string       `json:"version"`
		Origin      string       `json:"start_location"`
		Warehouse   string       `json:"destination_warehouse_id"`
		Expected    string       `json:"expected_arrival_at"`
		Notes       string       `json:"notes"`
	}
	if !decode(c, &in) {
		return
	}
	_, datesOK := date(in.Expected)
	if (in.Fulfillment != nil && !in.Fulfillment.valid()) || !required(in.Origin, 200) || !validID(in.Warehouse) || !datesOK || len(in.Notes) > 4000 {
		fail(c, 400, "Enter an origin, active destination warehouse and valid arrival date.")
		return
	}
	data, _ := json.Marshal(in)
	s.mutate(c, in.Version, func(ctx context.Context, q *database.Queries, id pgtype.UUID) error {
		warehouse, _ := uuid(in.Warehouse)
		if _, e := q.LockShipmentWarehouse(ctx, warehouse); e != nil {
			return rejected(c, 400, "Choose an active warehouse.")
		}
		before, e := q.GetShipment(ctx, database.GetShipmentParams{ID: id, Costs: true})
		if e != nil {
			return e
		}
		if e = q.UpdateOpenShipmentDetails(ctx, database.UpdateOpenShipmentDetailsParams{ID: id, Data: data}); e != nil {
			return e
		}
		after, e := q.GetShipment(ctx, database.GetShipmentParams{ID: id, Costs: true})
		if e != nil {
			return e
		}
		return audit(ctx, q, c, id, "shipments", "shipments.update", before, after)
	})
}
func (s *Service) DeleteStage(c *gin.Context) {
	var in struct {
		Version string `json:"version"`
		Reason  string `json:"reason"`
	}
	if !decode(c, &in) {
		return
	}
	if !required(in.Reason, 1000) {
		fail(c, 400, "Enter the reason for removing this unpaid stage.")
		return
	}
	child, e := uuid(c.Param("child"))
	if e != nil || !child.Valid {
		fail(c, 400, "Invalid transportation stage.")
		return
	}
	s.mutate(c, in.Version, func(ctx context.Context, q *database.Queries, id pgtype.UUID) error {
		before, e := q.GetShipmentStage(ctx, database.GetShipmentStageParams{ID: child, ShipmentID: id})
		if e != nil {
			return e
		}
		paid, e := q.ShipmentChildHasPayment(ctx, child)
		if e != nil {
			return e
		}
		if paid {
			return rejected(c, 409, "A stage linked to a payment cannot be deleted. Preserve its payment history.")
		}
		if _, e = q.DeleteUnpaidShipmentStage(ctx, database.DeleteUnpaidShipmentStageParams{ID: child, ShipmentID: id}); e != nil {
			return e
		}
		after, _ := json.Marshal(in)
		return audit(ctx, q, c, child, "transportation_stages", "transportation.delete", before, after)
	})
}
func (s *Service) UpdateWarehouse(c *gin.Context) {
	var in struct {
		Name    string `json:"name"`
		Address string `json:"address"`
		Active  bool   `json:"is_active"`
	}
	if !decode(c, &in) {
		return
	}
	if !required(in.Name, 200) || len(in.Address) > 2000 {
		fail(c, 400, "Enter a warehouse name and optional address.")
		return
	}
	id, ok := pathID(c)
	if !ok {
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
	before, e := q.GetManagedWarehouse(ctx, id)
	if e != nil {
		dbError(c, e)
		return
	}
	data, _ := json.Marshal(in)
	if e = q.UpdateManagedWarehouse(ctx, database.UpdateManagedWarehouseParams{ID: id, Data: data}); e == nil {
		e = audit(ctx, q, c, id, "warehouses", "warehouses.update", before, data)
	}
	if e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.Status(204)
}
