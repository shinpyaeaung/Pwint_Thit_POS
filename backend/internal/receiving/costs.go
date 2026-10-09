package receiving

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/costing"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

// Final costing and inventory posting share one transaction. A failed receipt
// leaves both the counts and costing editable; legacy finalized receipts remain valid.
func (s *Service) saveReceipt(c *gin.Context, in receiptInput) {
	ctx := c.Request.Context()
	actor, _ := authz.Principal(c)
	preview := strings.HasSuffix(c.FullPath(), "/preview")
	if in.Finalize || preview {
		for _, p := range []permissions.Code{permissions.CostsFinalize, permissions.FinanceViewLandedCost, permissions.ShipmentsView} {
			allowed, e := s.a.Allowed(c, p)
			if e != nil {
				fail(c, 503, "Authorization unavailable.")
				return
			}
			if !allowed {
				fail(c, 403, "Permission required to finalize receiving costs.")
				return
			}
		}
	}
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	id, _ := uuid(in.ShipmentID)
	parent, e := q.LockShipment(ctx, id)
	if e != nil {
		dbError(c, e)
		return
	}
	supplied := in.PreviewToken
	in.PreviewToken = ""
	if in.Finalize && !parent.CostsFinalizedAt.Valid {
		if parent.Status != "ARRIVED" || strconv.FormatInt(parent.Version, 10) != in.Version {
			fail(c, 409, "Shipment changed or has not arrived. Reload receiving.")
			return
		}
		if _, e = q.LockCostPurchaseItems(ctx, id); e != nil {
			dbError(c, e)
			return
		}
		raw, e := q.LandedCostSources(ctx, id)
		if e != nil {
			dbError(c, e)
			return
		}
		var source costing.Source
		if e = json.Unmarshal(raw, &source); e != nil {
			dbError(c, e)
			return
		}
		input, e := receiptCostInput(source, in)
		if e != nil {
			fail(c, 400, e.Error())
			return
		}
		result, e := costing.Calculate(source, input)
		if e != nil {
			fail(c, 400, e.Error())
			return
		}
		result.CountsConfirmed = true
		payload, _ := json.Marshal(in)
		hash := sha256.New()
		hash.Write(raw)
		hash.Write(payload)
		token := hex.EncodeToString(hash.Sum(nil))
		if preview {
			result.PreviewToken = token
			c.JSON(200, result)
			return
		}
		if supplied != token {
			fail(c, 409, "Counts or costs changed. Review the receipt again.")
			return
		}
		for _, item := range result.Items {
			row, _ := json.Marshal(item)
			if e = q.SaveCostItem(ctx, database.SaveCostItemParams{ShipmentID: id, Data: row}); e != nil {
				dbError(c, e)
				return
			}
		}
		result.Finalized = true
		document, _ := json.Marshal(result)
		if e = q.SaveCostDocument(ctx, database.SaveCostDocumentParams{ShipmentID: id, Document: document, FinalizedBy: actor.ID}); e != nil {
			dbError(c, e)
			return
		}
		if e = q.FinalizeShipmentCost(ctx, database.FinalizeShipmentCostParams{ID: id, CostsFinalizedBy: actor.ID, AllocationMethod: input.Method}); e != nil {
			dbError(c, e)
			return
		}
		if e = q.RecordProductAudit(ctx, database.RecordProductAuditParams{ActorID: actor.ID, Action: "costs.finalize", EntityType: "shipment_costings", EntityID: id, NewValue: document}); e != nil {
			dbError(c, e)
			return
		}
	}
	if preview {
		fail(c, 409, "Costs already finalized. Reload receiving.")
		return
	}
	// Deterministic normalization keeps identical retries identical after finalization.
	if in.Finalize {
		v, e := strconv.ParseInt(in.Version, 10, 64)
		if e != nil {
			fail(c, 400, "Invalid version.")
			return
		}
		in.Version = strconv.FormatInt(v+1, 10)
	}
	data, _ := json.Marshal(in)
	receipt, e := q.PostReceiving(ctx, database.PostReceivingParams{Data: data, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	if e = tx.Commit(ctx); e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": receipt})
}
func receiptCostInput(source costing.Source, in receiptInput) (costing.Input, error) {
	input := costing.Input{Version: in.Version, Method: "PURCHASE_VALUE", Notes: "Counts confirmed on goods receipt. " + in.Notes}
	expected := map[string]*big.Rat{}
	for _, item := range source.Items {
		expected[item.ID], _ = new(big.Rat).SetString(item.Expected)
	}
	for _, row := range in.Items {
		limit, ok := expected[row.ID]
		if !ok {
			return input, fmt.Errorf("Choose each shipment item once.")
		}
		delete(expected, row.ID)
		units, _ := new(big.Rat).SetString(row.Units)
		cartons, _ := new(big.Rat).SetString(row.Cartons)
		size := new(big.Rat)
		if row.CartonSize != "" {
			size.SetString(row.CartonSize)
		}
		received := new(big.Rat).Add(units, new(big.Rat).Mul(cartons, size))
		damaged, _ := new(big.Rat).SetString(row.Damaged)
		if received.Cmp(limit) > 0 || damaged.Cmp(received) > 0 {
			return input, fmt.Errorf("Received cannot exceed expected; damaged cannot exceed received.")
		}
		rounded, _ := new(big.Rat).SetString(received.FloatString(6))
		if rounded.Cmp(received) != 0 {
			return input, fmt.Errorf("Received quantity exceeds six decimal places.")
		}
		input.Items = append(input.Items, costing.InputItem{ID: row.ID, Received: received.FloatString(6), Damaged: row.Damaged, Sellable: new(big.Rat).Sub(received, damaged).FloatString(6)})
	}
	if len(expected) > 0 {
		return input, fmt.Errorf("Count every shipment item.")
	}
	return input, nil
}
