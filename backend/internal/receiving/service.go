package receiving

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"strings"
	"time"
)

type Service struct {
	q *database.Queries
	a *authz.Service
}

func New(db database.DBTX) *Service { return &Service{q: database.New(db)} }
func (s *Service) Register(r *gin.Engine, a *authz.Service) {
	s.a = a
	r.GET("/api/v1/batches", a.Require(permissions.InventoryView), s.Batches)
	r.GET("/api/v1/receiving", a.Require(permissions.ReceivingManage), s.List)
	r.GET("/api/v1/receiving/options", a.Require(permissions.ReceivingManage), s.Options)
	r.GET("/api/v1/receiving/shipments/:id", a.Require(permissions.ReceivingManage), s.Shipment)
	r.GET("/api/v1/receiving/:id", a.Require(permissions.ReceivingManage), s.Get)
	r.POST("/api/v1/receiving", a.Require(permissions.ReceivingManage), s.Post)
	r.GET("/api/v1/inventory", a.Require(permissions.InventoryView), s.Inventory)
	r.GET("/api/v1/inventory/warehouses", a.Require(permissions.InventoryView), s.Warehouses)
	r.GET("/api/v1/inventory/movements", a.Require(permissions.InventoryView), s.Movements)
	r.POST("/api/v1/inventory/adjustments", a.Require(permissions.InventoryAdjust), s.Adjust)
}
func response(c *gin.Context, b []byte, e error) {
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", b)
}
func (s *Service) List(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	q := c.Query("q")
	if len(q) > 200 {
		fail(c, 400, "Search is too long.")
		return
	}
	b, e := s.q.ListReceiving(c.Request.Context(), database.ListReceivingParams{Search: q, PageSize: size, PageOffset: offset})
	response(c, b, e)
}
func (s *Service) Options(c *gin.Context) {
	q := c.Query("q")
	if len(q) > 200 {
		fail(c, 400, "Search is too long.")
		return
	}
	b, e := s.q.ReceivingOptions(c.Request.Context(), q)
	response(c, b, e)
}
func (s *Service) Get(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.GetReceiving(c.Request.Context(), id)
	response(c, b, e)
}
func (s *Service) Shipment(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	b, e := s.q.ReceivingShipment(c.Request.Context(), id)
	response(c, b, e)
}
func (s *Service) Warehouses(c *gin.Context) {
	b, e := s.q.InventoryWarehouses(c.Request.Context())
	response(c, b, e)
}
func optionalID(c *gin.Context, name string) (pgtype.UUID, bool) {
	id, e := uuid(c.Query(name))
	if e != nil {
		fail(c, 400, "Invalid reference ID.")
		return id, false
	}
	return id, true
}
func (s *Service) Inventory(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	id, ok := optionalID(c, "warehouse_id")
	if !ok {
		return
	}
	q := c.Query("q")
	if len(q) > 200 {
		fail(c, 400, "Search is too long.")
		return
	}
	costs, e := s.a.Allowed(c, permissions.FinanceViewLandedCost)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return
	}
	b, e := s.q.ListInventory(c.Request.Context(), database.ListInventoryParams{Search: q, WarehouseID: id, PageSize: size, PageOffset: offset, Costs: costs})
	response(c, b, e)
}
func (s *Service) Movements(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	batch, ok := optionalID(c, "batch_id")
	if !ok {
		return
	}
	warehouse, ok := optionalID(c, "warehouse_id")
	if !ok {
		return
	}
	costs, e := s.a.Allowed(c, permissions.FinanceViewLandedCost)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return
	}
	b, e := s.q.InventoryMovements(c.Request.Context(), database.InventoryMovementsParams{BatchID: batch, WarehouseID: warehouse, PageSize: size, PageOffset: offset, Costs: costs})
	response(c, b, e)
}
func validID(v string) bool     { id, e := uuid(v); return e == nil && id.Valid }
func text(v string, n int) bool { return strings.TrimSpace(v) != "" && len(v) <= n }
func decimal(v string, signed bool) bool {
	if signed {
		v = strings.TrimPrefix(v, "-")
	}
	p := strings.Split(v, ".")
	if len(p) > 2 || len(p[0]) == 0 || len(p[0]) > 14 || len(p) == 2 && (len(p[1]) == 0 || len(p[1]) > 6) {
		return false
	}
	for _, part := range p {
		for _, r := range part {
			if r < '0' || r > '9' {
				return false
			}
		}
	}
	return true
}
func day(v string) bool {
	if v == "" {
		return true
	}
	_, e := time.Parse("2006-01-02", v)
	return e == nil
}

type receiptItem struct {
	ID           string `json:"shipment_item_id"`
	CartonSize   string `json:"carton_size"`
	Cartons      string `json:"received_cartons"`
	Units        string `json:"received_units"`
	Damaged      string `json:"damaged_quantity"`
	Batch        string `json:"batch_number"`
	Manufactured string `json:"manufactured_on"`
	Expires      string `json:"expires_on"`
	Notes        string `json:"notes"`
}

func (s *Service) Post(c *gin.Context) {
	var in struct {
		RequestID  string        `json:"request_id"`
		ShipmentID string        `json:"shipment_id"`
		Version    string        `json:"version"`
		Number     string        `json:"receipt_number"`
		Received   string        `json:"received_at"`
		Notes      string        `json:"notes"`
		Items      []receiptItem `json:"items"`
	}
	if !decode(c, &in) {
		return
	}
	in.Number = strings.TrimSpace(in.Number)
	_, e := time.Parse(time.RFC3339, in.Received)
	if !validID(in.RequestID) || !validID(in.ShipmentID) || !text(in.Number, 100) || !text(in.Version, 20) || e != nil || len(in.Notes) > 4000 || len(in.Items) < 1 || len(in.Items) > 100 {
		fail(c, 400, "Enter a receipt number, shipment, receiving date and all item counts.")
		return
	}
	for _, x := range in.Items {
		if !validID(x.ID) || !decimal(x.Cartons, false) || !decimal(x.Units, false) || !decimal(x.Damaged, false) || x.CartonSize != "" && !decimal(x.CartonSize, false) || !text(x.Batch, 100) || !day(x.Manufactured) || !day(x.Expires) || len(x.Notes) > 2000 {
			fail(c, 400, "Enter valid non-negative quantities, batch numbers and dates.")
			return
		}
	}
	data, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	id, e := s.q.PostReceiving(c.Request.Context(), database.PostReceivingParams{Data: data, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": id})
}
func (s *Service) Adjust(c *gin.Context) {
	var in struct {
		RequestID   string `json:"request_id"`
		WarehouseID string `json:"warehouse_id"`
		BatchID     string `json:"batch_id"`
		Version     string `json:"version"`
		Bucket      string `json:"bucket"`
		Delta       string `json:"quantity_delta"`
		Reason      string `json:"reason"`
	}
	if !decode(c, &in) {
		return
	}
	if !validID(in.RequestID) || !validID(in.WarehouseID) || !validID(in.BatchID) || !text(in.Version, 20) || !decimal(in.Delta, true) || !text(in.Reason, 1000) || (in.Bucket != "SELLABLE" && in.Bucket != "DAMAGED" && in.Bucket != "RESERVED") {
		fail(c, 400, "Enter a stock bucket, non-zero quantity change and reason.")
		return
	}
	data, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	id, e := s.q.AdjustInventory(c.Request.Context(), database.AdjustInventoryParams{Data: data, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": id})
}
