package receiving

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"log/slog"
	"regexp"
)

var transferQuantity = regexp.MustCompile(`^\d{1,14}(\.\d{1,6})?$`)

func (s *Service) registerTransfers(r *gin.Engine, a *authz.Service) {
	manage := permissions.Code("stock_transfers.manage")
	r.GET("/api/v1/transfers/:id", a.Require(permissions.ShipmentsView), s.Transfer)
	r.POST("/api/v1/transfers", a.Require(manage), a.Require(permissions.InventoryView), s.DispatchTransfer)
	r.POST("/api/v1/transfers/:id/receive", a.Require(manage), a.Require(permissions.ReceivingManage), a.Require(permissions.CostsFinalize), a.Require(permissions.FinanceViewLandedCost), a.Require(permissions.ShipmentsViewCost), s.ReceiveTransfer)
	r.POST("/api/v1/transfers/:id/cancel", a.Require(manage), s.CancelTransfer)
}
func (s *Service) Transfer(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	costs, e := s.a.Allowed(c, permissions.FinanceViewLandedCost)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return
	}
	b, e := s.q.GetTransfer(c.Request.Context(), database.GetTransferParams{ShipmentID: id, Costs: costs})
	response(c, b, e)
}
func (s *Service) DispatchTransfer(c *gin.Context) {
	var in struct {
		Request string `json:"request_id"`
		From    string `json:"from_warehouse_id"`
		To      string `json:"to_warehouse_id"`
		Notes   string `json:"notes"`
		Items   []struct {
			Batch    string `json:"batch_id"`
			Version  string `json:"version"`
			Quantity string `json:"quantity"`
		} `json:"items"`
	}
	if !decode(c, &in) {
		return
	}
	for _, v := range []string{in.Request, in.From, in.To} {
		id, e := uuid(v)
		if e != nil || !id.Valid {
			fail(c, 400, "Choose valid warehouses and request ID.")
			return
		}
	}
	if len(in.Items) < 1 || len(in.Items) > 100 || len(in.Notes) > 4000 {
		fail(c, 400, "Choose 1–100 batches and valid notes.")
		return
	}
	for _, i := range in.Items {
		id, e := uuid(i.Batch)
		if e != nil || !id.Valid || !transferQuantity.MatchString(i.Quantity) || len(i.Version) > 30 {
			fail(c, 400, "Enter valid batch quantities.")
			return
		}
	}
	actor, _ := authz.Principal(c)
	d, _ := json.Marshal(in)
	id, e := s.q.DispatchTransfer(c.Request.Context(), database.DispatchTransferParams{Data: d, Actor: actor.ID})
	if e != nil {
		slog.Error("warehouse transfer failed", "error", e)
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": id})
}
func (s *Service) ReceiveTransfer(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	var in struct {
		Shipment string `json:"shipment_id"`
		Version  string `json:"version"`
		Items    []struct {
			ID       string `json:"id"`
			Received string `json:"received_quantity"`
			Damaged  string `json:"damaged_quantity"`
			Notes    string `json:"notes"`
		} `json:"items"`
	}
	if !decode(c, &in) {
		return
	}
	in.Shipment = c.Param("id")
	if len(in.Items) < 1 || len(in.Items) > 100 || len(in.Version) > 30 {
		fail(c, 400, "Reconcile every transfer item.")
		return
	}
	for _, i := range in.Items {
		ref, e := uuid(i.ID)
		if e != nil || !ref.Valid || !transferQuantity.MatchString(i.Received) || !transferQuantity.MatchString(i.Damaged) || len(i.Notes) > 1000 {
			fail(c, 400, "Enter valid arrival counts and notes.")
			return
		}
	}
	actor, _ := authz.Principal(c)
	d, _ := json.Marshal(in)
	_, e := s.q.ReceiveTransfer(c.Request.Context(), database.ReceiveTransferParams{Data: d, Actor: actor.ID})
	if e != nil {
		slog.Error("warehouse transfer failed", "error", e)
		dbError(c, e)
		return
	}
	c.JSON(200, gin.H{"id": id})
}
func (s *Service) CancelTransfer(c *gin.Context) {
	_, ok := pathID(c)
	if !ok {
		return
	}
	var in struct {
		Shipment string `json:"shipment_id"`
		Version  string `json:"version"`
		Reason   string `json:"reason"`
	}
	if !decode(c, &in) {
		return
	}
	in.Shipment = c.Param("id")
	if len(in.Version) > 30 || len(in.Reason) > 1000 {
		fail(c, 400, "Enter a valid return reason.")
		return
	}
	actor, _ := authz.Principal(c)
	d, _ := json.Marshal(in)
	if e := s.q.CancelTransfer(c.Request.Context(), database.CancelTransferParams{Data: d, Actor: actor.ID}); e != nil {
		slog.Error("warehouse transfer failed", "error", e)
		dbError(c, e)
		return
	}
	c.Status(204)
}
