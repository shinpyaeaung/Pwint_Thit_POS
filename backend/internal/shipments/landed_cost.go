package shipments

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/costing"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
)

func (s *Service) Cost(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	source, e := s.q.LandedCostSources(c.Request.Context(), id)
	if e != nil {
		dbError(c, e)
		return
	}
	snapshot, e := s.q.GetFinalizedCost(c.Request.Context(), id)
	if e != nil && !errors.Is(e, pgx.ErrNoRows) {
		dbError(c, e)
		return
	}
	var saved any
	if len(snapshot) > 0 {
		saved = json.RawMessage(snapshot)
	}
	c.JSON(200, gin.H{"source": json.RawMessage(source), "snapshot": saved})
}
func (s *Service) PreviewCost(c *gin.Context)  { s.calculateCost(c, false) }
func (s *Service) FinalizeCost(c *gin.Context) { s.calculateCost(c, true) }
func (s *Service) calculateCost(c *gin.Context, final bool) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	var in costing.Input
	if !decode(c, &in) {
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	parent, e := q.LockShipment(ctx, id)
	if e != nil {
		dbError(c, e)
		return
	}
	if parent.CostsFinalizedAt.Valid || parent.Status == "CANCELLED" || in.Version != strconv.FormatInt(parent.Version, 10) {
		fail(c, 409, "Shipment changed, was cancelled or already finalized. Reload its costing.")
		return
	}
	if final && parent.Status != "ARRIVED" {
		fail(c, 409, "Mark the shipment arrived and confirm sellable quantities before finalizing costs.")
		return
	}
	if final && !required(in.Notes, 2000) {
		fail(c, 400, "Add a confirmation note for the sellable quantities and costs.")
		return
	}
	// Serialize split-shipment costing against other finalizations of these purchase items.
	if _, e = q.LockCostPurchaseItems(ctx, id); e != nil {
		dbError(c, e)
		return
	}
	data, e := q.LandedCostSources(ctx, id)
	if e != nil {
		dbError(c, e)
		return
	}
	var source costing.Source
	if e = json.Unmarshal(data, &source); e != nil {
		dbError(c, e)
		return
	}
	result, e := costing.Calculate(source, in)
	if e != nil {
		fail(c, 400, e.Error())
		return
	}
	supplied := in.PreviewToken
	in.PreviewToken = ""
	input, _ := json.Marshal(in)
	h := sha256.New()
	h.Write(data)
	h.Write(input)
	token := hex.EncodeToString(h.Sum(nil))
	result.PreviewToken = token
	if !final {
		c.JSON(200, result)
		return
	}
	if supplied != token {
		fail(c, 409, "Cost inputs or source amounts changed. Calculate and review a new preview before finalizing.")
		return
	}
	actor, _ := authz.Principal(c)
	for _, item := range result.Items {
		row, _ := json.Marshal(item)
		if e = q.SaveCostItem(ctx, database.SaveCostItemParams{ShipmentID: id, Data: row}); e != nil {
			dbError(c, e)
			return
		}
	}
	result.Finalized = true
	result.PreviewToken = ""
	document, _ := json.Marshal(result)
	if e = q.SaveCostDocument(ctx, database.SaveCostDocumentParams{ShipmentID: id, Document: document, FinalizedBy: actor.ID}); e != nil {
		dbError(c, e)
		return
	}
	if e = q.FinalizeShipmentCost(ctx, database.FinalizeShipmentCostParams{ID: id, CostsFinalizedBy: actor.ID, AllocationMethod: in.Method}); e != nil {
		dbError(c, e)
		return
	}
	if e = audit(ctx, q, c, id, "shipment_costings", "costs.finalize", nil, document); e != nil {
		dbError(c, e)
		return
	}
	if e = tx.Commit(ctx); e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, result)
}
