package shipments

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"math/big"
	"sort"
	"strconv"
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
	r.GET("/api/v1/shipments/:id/landed-cost", a.Require(permissions.ShipmentsView), a.Require(permissions.FinanceViewLandedCost), s.Cost)
	r.POST("/api/v1/shipments/:id/landed-cost/preview", a.Require(permissions.ShipmentsView), a.Require(permissions.FinanceViewLandedCost), s.PreviewCost)
	r.POST("/api/v1/shipments/:id/landed-cost/finalize", a.Require(permissions.ShipmentsView), a.Require(permissions.FinanceViewLandedCost), a.Require(permissions.CostsFinalize), s.FinalizeCost)
	r.GET("/api/v1/shipments", a.Require(permissions.ShipmentsView), s.List)
	r.GET("/api/v1/shipments/:id", a.Require(permissions.ShipmentsView), s.Get)
	r.GET("/api/v1/shipments/:id/items", a.Require(permissions.ShipmentsView), s.Items)
	r.GET("/api/v1/shipments/:id/stages", a.Require(permissions.ShipmentsView), s.Stages)
	r.GET("/api/v1/shipments/:id/expenses", a.Require(permissions.ShipmentsView), s.Expenses)
	r.GET("/api/v1/shipment-options", a.Require(permissions.ShipmentsManage), s.Options)
	r.POST("/api/v1/warehouses", a.Require(permissions.SettingsManage), s.CreateWarehouse)
	r.POST("/api/v1/shipments", a.Require(permissions.ShipmentsManage), s.Create)
	r.PUT("/api/v1/shipments/:id/status", a.Require(permissions.ShipmentsManage), s.Status)
	r.POST("/api/v1/shipments/:id/stages", a.Require(permissions.TransportationManage), a.Require(permissions.ShipmentsViewCost), s.SaveStage)
	r.PUT("/api/v1/shipments/:id/stages/:child", a.Require(permissions.TransportationManage), a.Require(permissions.ShipmentsViewCost), a.Require(permissions.ChangeTransportCost), s.SaveStage)
	r.POST("/api/v1/shipments/:id/expenses", a.Require(permissions.TransportationManage), a.Require(permissions.ShipmentsViewCost), s.AddExpense)
	r.POST("/api/v1/shipments/:id/expenses/:child/void", a.Require(permissions.TransportationManage), a.Require(permissions.ShipmentsViewCost), a.Require(permissions.ChangeTransportCost), s.VoidExpense)
}
func respond(c *gin.Context, v []byte, e error) {
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(200, "application/json", v)
}
func (s *Service) costs(c *gin.Context) (bool, bool) {
	v, e := s.a.Allowed(c, permissions.ShipmentsViewCost)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return false, false
	}
	return v, true
}
func (s *Service) Get(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	cost, ok := s.costs(c)
	if !ok {
		return
	}
	v, e := s.q.GetShipment(c.Request.Context(), database.GetShipmentParams{ID: id, Costs: cost})
	respond(c, v, e)
}
func (s *Service) Items(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	v, e := s.q.ShipmentItems(c.Request.Context(), id)
	respond(c, v, e)
}
func (s *Service) Stages(c *gin.Context)   { s.children(c, true) }
func (s *Service) Expenses(c *gin.Context) { s.children(c, false) }
func (s *Service) children(c *gin.Context, stage bool) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	cost, ok := s.costs(c)
	if !ok {
		return
	}
	var v []byte
	var e error
	if stage {
		v, e = s.q.ShipmentStages(c.Request.Context(), database.ShipmentStagesParams{ShipmentID: id, Costs: cost, PageSize: size, PageOffset: offset})
	} else {
		v, e = s.q.ShipmentExpenses(c.Request.Context(), database.ShipmentExpensesParams{ShipmentID: id, Costs: cost, PageSize: size, PageOffset: offset})
	}
	respond(c, v, e)
}
func (s *Service) List(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	cost, ok := s.costs(c)
	if !ok {
		return
	}
	search, status := c.Query("q"), c.Query("status")
	if len(search) > 200 || (status != "" && status != "PREPARING" && status != "IN_TRANSIT" && status != "ARRIVED" && status != "RECEIVED" && status != "CANCELLED") {
		fail(c, 400, "Invalid shipment filters.")
		return
	}
	v, e := s.q.ListShipments(c.Request.Context(), database.ListShipmentsParams{Search: search, Status: status, Costs: cost, PageSize: size, PageOffset: offset})
	respond(c, v, e)
}
func (s *Service) Options(c *gin.Context) {
	if c.Query("kind") == "warehouses" {
		v, e := s.q.ShipmentWarehouses(c.Request.Context())
		respond(c, v, e)
		return
	}
	q := strings.TrimSpace(c.Query("q"))
	if c.Query("kind") != "purchases" || len(q) > 200 {
		fail(c, 400, "Invalid reference search.")
		return
	}
	v, e := s.q.ShipmentPurchaseChoices(c.Request.Context(), q)
	respond(c, v, e)
}
func decimal(v string, whole, scale int, positive bool) bool {
	parts := strings.Split(v, ".")
	if len(parts) > 2 || len(parts[0]) == 0 || len(parts[0]) > whole {
		return false
	}
	if len(parts) == 2 && (len(parts[1]) == 0 || len(parts[1]) > scale) {
		return false
	}
	for _, p := range parts {
		for _, r := range p {
			if r < '0' || r > '9' {
				return false
			}
		}
	}
	n, ok := new(big.Rat).SetString(v)
	return ok && (!positive || n.Sign() > 0)
}
func required(v string, max int) bool { return strings.TrimSpace(v) != "" && len(v) <= max }
func validID(v string) bool           { id, e := uuid(v); return e == nil && id.Valid }
func date(v string) (pgtype.Timestamptz, bool) {
	if v == "" {
		return pgtype.Timestamptz{}, true
	}
	t, e := time.Parse(time.RFC3339, v)
	return pgtype.Timestamptz{Time: t, Valid: e == nil}, e == nil
}
func audit(ctx context.Context, q *database.Queries, c *gin.Context, id pgtype.UUID, kind, action string, before, after []byte) error {
	actor, _ := authz.Principal(c)
	return q.RecordProductAudit(ctx, database.RecordProductAuditParams{ActorID: actor.ID, EntityID: id, EntityType: kind, Action: action, OldValue: before, NewValue: after})
}
func (s *Service) CreateWarehouse(c *gin.Context) {
	var in struct {
		Code    string `json:"code"`
		Name    string `json:"name"`
		Address string `json:"address"`
	}
	if !decode(c, &in) {
		return
	}
	in.Code = strings.TrimSpace(in.Code)
	in.Name = strings.TrimSpace(in.Name)
	if !required(in.Code, 100) || !required(in.Name, 200) || len(in.Address) > 2000 {
		fail(c, 400, "Enter a warehouse code, name and optional address.")
		return
	}
	tx, e := s.db.Begin(c.Request.Context())
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	id, e := q.CreateShipmentWarehouse(c.Request.Context(), database.CreateShipmentWarehouseParams{Code: in.Code, Name: in.Name, Address: pgtype.Text{String: in.Address, Valid: in.Address != ""}})
	if e == nil {
		data, _ := json.Marshal(in)
		e = audit(c.Request.Context(), q, c, id, "warehouses", "warehouses.create", nil, data)
	}
	if e == nil {
		e = tx.Commit(c.Request.Context())
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": id})
}

type shipmentInput struct {
	RequestID string `json:"request_id"`
	Number    string `json:"shipment_number"`
	Origin    string `json:"start_location"`
	Warehouse string `json:"destination_warehouse_id"`
	Expected  string `json:"expected_arrival_at"`
	Notes     string `json:"notes"`
	Items     []struct {
		PurchaseItem string `json:"purchase_item_id"`
		Quantity     string `json:"expected_quantity"`
	} `json:"items"`
}

func (s *Service) Create(c *gin.Context) {
	var in shipmentInput
	if !decode(c, &in) {
		return
	}
	in.Number = strings.TrimSpace(in.Number)
	in.Origin = strings.TrimSpace(in.Origin)
	_, datesOK := date(in.Expected)
	if !validID(in.RequestID) || !validID(in.Warehouse) || !required(in.Number, 100) || !required(in.Origin, 200) || len(in.Notes) > 4000 || !datesOK || len(in.Items) == 0 || len(in.Items) > 100 {
		fail(c, 400, "Enter shipment identity, destination and 1–100 valid purchase items.")
		return
	}
	seen := map[string]bool{}
	for _, item := range in.Items {
		if !validID(item.PurchaseItem) || !decimal(item.Quantity, 14, 6, true) || seen[item.PurchaseItem] {
			fail(c, 400, "Items must be distinct with positive base-unit quantities.")
			return
		}
		seen[item.PurchaseItem] = true
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
	warehouse, _ := uuid(in.Warehouse)
	if _, e = q.LockShipmentWarehouse(ctx, warehouse); e != nil {
		fail(c, 400, "Choose an active warehouse.")
		return
	}
	data, _ := json.Marshal(in)
	actor, _ := authz.Principal(c)
	id, e := q.InsertShipment(ctx, database.InsertShipmentParams{Data: data, Actor: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	sort.Slice(in.Items, func(i, j int) bool { return in.Items[i].PurchaseItem < in.Items[j].PurchaseItem })
	for _, item := range in.Items {
		pid, _ := uuid(item.PurchaseItem)
		p, err := q.LockShipmentPurchaseItem(ctx, pid)
		if err != nil {
			fail(c, 400, "Only posted purchase items can be shipped.")
			return
		}
		reserved, err := q.ShipmentReservedQuantity(ctx, pid)
		if err != nil {
			dbError(c, err)
			return
		}
		base, _ := new(big.Rat).SetString(p.BaseQuantity)
		used, _ := new(big.Rat).SetString(reserved)
		wanted, _ := new(big.Rat).SetString(item.Quantity)
		if wanted.Cmp(new(big.Rat).Sub(base, used)) > 0 {
			fail(c, 409, "A purchase item has insufficient unshipped quantity. Refresh and review quantities.")
			return
		}
		var qty pgtype.Numeric
		_ = qty.Scan(item.Quantity)
		if e = q.InsertShipmentItem(ctx, database.InsertShipmentItemParams{ShipmentID: id, PurchaseItemID: pid, ProductID: p.ProductID, ExpectedQuantity: qty}); e != nil {
			dbError(c, e)
			return
		}
	}
	after, e := q.GetShipment(ctx, database.GetShipmentParams{ID: id, Costs: false})
	if e == nil {
		e = audit(ctx, q, c, id, "shipments", "shipments.create", nil, data)
	}
	if e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.Data(201, "application/json", after)
}
func (s *Service) mutate(c *gin.Context, version string, fn func(context.Context, *database.Queries, pgtype.UUID) error) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	old, e := q.LockShipment(ctx, id)
	if e != nil {
		dbError(c, e)
		return
	}
	if version != strconv.FormatInt(old.Version, 10) || old.CostsFinalizedAt.Valid || old.Status == "CANCELLED" || old.Status == "RECEIVED" {
		fail(c, 409, "Shipment changed, is closed, or has finalized costs. Reload its details.")
		return
	}
	if e = fn(ctx, q, id); e != nil {
		if !c.IsAborted() {
			dbError(c, e)
		}
		return
	}
	if e = q.TouchShipment(ctx, id); e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.Status(204)
}
func rejected(c *gin.Context, status int, message string) error {
	fail(c, status, message)
	return pgx.ErrNoRows
}
func (s *Service) Status(c *gin.Context) {
	var in struct {
		Version string `json:"version"`
		Status  string `json:"status"`
		Shipped string `json:"shipped_at"`
		Arrived string `json:"arrived_at"`
	}
	if !decode(c, &in) {
		return
	}
	shipped, ok := date(in.Shipped)
	arrived, ok2 := date(in.Arrived)
	if !ok || !ok2 {
		fail(c, 400, "Invalid shipment dates.")
		return
	}
	s.mutate(c, in.Version, func(ctx context.Context, q *database.Queries, id pgtype.UUID) error {
		old, e := q.LockShipment(ctx, id)
		if e != nil {
			return e
		}
		valid := (old.Status == "PREPARING" && in.Status == "IN_TRANSIT") || (old.Status == "IN_TRANSIT" && in.Status == "ARRIVED") || ((old.Status == "PREPARING" || old.Status == "IN_TRANSIT") && in.Status == "CANCELLED")
		if !valid {
			return rejected(c, 409, "Choose the next shipment status. Receiving is recorded through goods receiving.")
		}
		if in.Status == "IN_TRANSIT" && !shipped.Valid {
			return rejected(c, 400, "Supply the shipment departure date.")
		}
		if in.Status == "ARRIVED" && (!arrived.Valid || !old.ShippedAt.Valid || arrived.Time.Before(old.ShippedAt.Time)) {
			return rejected(c, 400, "Arrival must be on or after shipment departure.")
		}
		if in.Status != "ARRIVED" {
			arrived = pgtype.Timestamptz{}
		}
		if in.Status == "CANCELLED" {
			shipped = pgtype.Timestamptz{}
			has, e := q.ShipmentHasReceiving(ctx, id)
			if e != nil {
				return e
			}
			if has {
				return rejected(c, 409, "A shipment with receiving records cannot be cancelled.")
			}
		}
		before, e := q.GetShipment(ctx, database.GetShipmentParams{ID: id, Costs: false})
		if e != nil {
			return e
		}
		if e = q.UpdateShipmentStatus(ctx, database.UpdateShipmentStatusParams{ID: id, Status: in.Status, ShippedAt: shipped, ArrivedAt: arrived}); e != nil {
			return e
		}
		after, e := q.GetShipment(ctx, database.GetShipmentParams{ID: id, Costs: false})
		if e != nil {
			return e
		}
		return audit(ctx, q, c, id, "shipments", "shipments.status", before, after)
	})
}
