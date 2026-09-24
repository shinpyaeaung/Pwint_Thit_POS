package shipments

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
	"net/http"
	"strings"
)

type stageInput struct {
	Version     string `json:"version"`
	RequestID   string `json:"request_id"`
	Origin      string `json:"start_location"`
	Destination string `json:"destination"`
	Provider    string `json:"provider_name"`
	Type        string `json:"transportation_type"`
	Vehicle     string `json:"vehicle_information"`
	Departed    string `json:"departed_at"`
	Arrived     string `json:"arrived_at"`
	Fee         string `json:"transportation_fee_mmk"`
	Loading     string `json:"loading_fee_mmk"`
	Unloading   string `json:"unloading_fee_mmk"`
	Other       string `json:"other_fee_mmk"`
	Notes       string `json:"notes"`
}

func (s *Service) SaveStage(c *gin.Context) {
	var in stageInput
	if !decode(c, &in) {
		return
	}
	in.Origin = strings.TrimSpace(in.Origin)
	in.Destination = strings.TrimSpace(in.Destination)
	in.Provider = strings.TrimSpace(in.Provider)
	dep, ok := date(in.Departed)
	arr, ok2 := date(in.Arrived)
	updating := c.Request.Method == http.MethodPut
	if !required(in.Origin, 200) || !required(in.Destination, 200) || !required(in.Provider, 200) || len(in.Type) > 100 || len(in.Vehicle) > 200 || len(in.Notes) > 4000 || !ok || !ok2 || (arr.Valid && (!dep.Valid || arr.Time.Before(dep.Time))) || (!updating && !validID(in.RequestID)) {
		fail(c, 400, "Enter stage locations/provider and valid dates. Arrival requires an earlier departure.")
		return
	}
	for _, v := range []string{in.Fee, in.Loading, in.Unloading, in.Other} {
		if !decimal(v, 16, 4, false) {
			fail(c, 400, "Fees must be non-negative MMK amounts with up to four decimal places.")
			return
		}
	}
	child, e := uuid(c.Param("child"))
	if updating && (e != nil || !child.Valid) {
		fail(c, 400, "Invalid stage ID.")
		return
	}
	data, _ := json.Marshal(in)
	s.mutate(c, in.Version, func(ctx context.Context, q *database.Queries, id pgtype.UUID) error {
		var before []byte
		var err error
		action := "transportation.create"
		if updating {
			action = "transportation.update"
			before, err = q.GetShipmentStage(ctx, database.GetShipmentStageParams{ID: child, ShipmentID: id})
			if err != nil {
				return err
			}
			paid, err := q.ShipmentChildHasPayment(ctx, child)
			if err != nil {
				return err
			}
			if paid {
				return rejected(c, 409, "A stage with payment allocations cannot be changed. Use the payment adjustment workflow.")
			}
			_, err = q.UpdateShipmentStage(ctx, database.UpdateShipmentStageParams{ID: child, ShipmentID: id, Data: data})
			if err != nil {
				return err
			}
		} else {
			child, err = q.InsertShipmentStage(ctx, database.InsertShipmentStageParams{ShipmentID: id, Data: data})
			if err != nil {
				return err
			}
		}
		after, err := q.GetShipmentStage(ctx, database.GetShipmentStageParams{ID: child, ShipmentID: id})
		if err != nil {
			return err
		}
		return audit(ctx, q, c, child, "transportation_stages", action, before, after)
	})
}
func (s *Service) AddExpense(c *gin.Context) {
	var in struct {
		Version     string `json:"version"`
		RequestID   string `json:"request_id"`
		Category    string `json:"category"`
		Description string `json:"description"`
		Currency    string `json:"currency_code"`
		Amount      string `json:"amount_original"`
		Rate        string `json:"mmk_per_unit"`
		Incurred    string `json:"incurred_at"`
		Notes       string `json:"notes"`
	}
	if !decode(c, &in) {
		return
	}
	when, ok := date(in.Incurred)
	if !validID(in.RequestID) || !required(in.Category, 100) || !required(in.Description, 1000) || len(in.Notes) > 4000 || len(in.Currency) != 3 || !ok || !when.Valid || !decimal(in.Amount, 16, 4, true) || !decimal(in.Rate, 14, 10, true) {
		fail(c, 400, "Enter an expense description, date, currency, positive amount and rate.")
		return
	}
	if in.Currency == "MMK" {
		if !decimalOne(in.Rate) {
			fail(c, 400, "MMK uses a fixed rate of 1.")
			return
		}
	} else {
		allowed, e := s.a.Allowed(c, permissions.ExchangeRatesManage)
		if e != nil {
			fail(c, 503, "Authorization unavailable.")
			return
		}
		if !allowed {
			fail(c, 403, "Foreign expense rates require exchange_rates.manage.")
			return
		}
	}
	data, _ := json.Marshal(in)
	s.mutate(c, in.Version, func(ctx context.Context, q *database.Queries, id pgtype.UUID) error {
		if _, e := q.LockPurchaseCurrency(ctx, in.Currency); e != nil {
			return rejected(c, 400, "Choose an active currency.")
		}
		actor, _ := authz.Principal(c)
		child, e := q.InsertShipmentExpense(ctx, database.InsertShipmentExpenseParams{ShipmentID: id, Actor: actor.ID, Data: data})
		if e != nil {
			return e
		}
		after, e := q.GetShipmentExpense(ctx, database.GetShipmentExpenseParams{ID: child, ShipmentID: id})
		if e != nil {
			return e
		}
		return audit(ctx, q, c, child, "shipment_expenses", "shipment_expenses.create", nil, after)
	})
}
func decimalOne(v string) bool {
	v = strings.TrimLeft(v, "0")
	return v == "1" || strings.HasPrefix(v, "1.") && strings.Trim(v[2:], "0") == ""
}
func (s *Service) VoidExpense(c *gin.Context) {
	var in struct {
		Version string `json:"version"`
		Reason  string `json:"reason"`
	}
	if !decode(c, &in) {
		return
	}
	child, e := uuid(c.Param("child"))
	if e != nil || !child.Valid || !required(in.Reason, 1000) {
		fail(c, 400, "Provide the expense ID and a void reason.")
		return
	}
	s.mutate(c, in.Version, func(ctx context.Context, q *database.Queries, id pgtype.UUID) error {
		before, e := q.GetShipmentExpense(ctx, database.GetShipmentExpenseParams{ID: child, ShipmentID: id})
		if e != nil {
			return e
		}
		paid, e := q.ShipmentChildHasPayment(ctx, child)
		if e != nil {
			return e
		}
		if paid {
			return rejected(c, 409, "An expense with payment allocations cannot be voided.")
		}
		n, e := q.VoidShipmentExpense(ctx, database.VoidShipmentExpenseParams{ID: child, ShipmentID: id, Reason: pgtype.Text{String: in.Reason, Valid: true}})
		if e != nil {
			return e
		}
		if n == 0 {
			return rejected(c, 409, "Expense is already voided.")
		}
		after, e := q.GetShipmentExpense(ctx, database.GetShipmentExpenseParams{ID: child, ShipmentID: id})
		if e != nil {
			return e
		}
		return audit(ctx, q, c, child, "shipment_expenses", "shipment_expenses.void", before, after)
	})
}
