package purchasing

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"strings"
	"time"
)

func (s *Service) Rates(c *gin.Context) {
	currency := c.Query("currency")
	when, e := time.Parse(time.RFC3339, c.DefaultQuery("as_of", time.Now().UTC().Format(time.RFC3339)))
	if e != nil || !currencyPattern.MatchString(currency) {
		fail(c, 400, "Choose a currency and valid as-of date.")
		return
	}
	v, e := s.q.PurchaseRates(c.Request.Context(), database.PurchaseRatesParams{Currency: currency, AsOf: pgtype.Timestamptz{Time: when, Valid: true}})
	respond(c, v, e)
}
func (s *Service) CreateRate(c *gin.Context) {
	var in struct {
		Currency  string `json:"currency_code"`
		Rate      string `json:"mmk_per_unit"`
		Effective string `json:"effective_at"`
		Source    string `json:"source"`
	}
	if !decode(c, &in) {
		return
	}
	in.Source = strings.TrimSpace(in.Source)
	when, e := time.Parse(time.RFC3339, in.Effective)
	if e != nil || !currencyPattern.MatchString(in.Currency) || !decimal(in.Rate, 14, 10, true) || len(in.Source) == 0 || len(in.Source) > 500 || (in.Currency == "MMK" && !sameNumber(in.Rate, "1")) {
		fail(c, 400, "Enter a currency, positive rate, valid effective date and source (up to 500 bytes). MMK is fixed at 1.")
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	tx, e := s.db.Begin(ctx)
	if e != nil {
		dbError(c, e)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	actor, _ := authz.Principal(c)
	var rate pgtype.Numeric
	_ = rate.Scan(in.Rate)
	id, e := q.CreatePurchaseRate(ctx, database.CreatePurchaseRateParams{CurrencyCode: in.Currency, MmkPerUnit: rate, EffectiveAt: pgtype.Timestamptz{Time: when, Valid: true}, Source: in.Source, RecordedBy: actor.ID})
	if e != nil {
		dbError(c, e)
		return
	}
	data, _ := json.Marshal(in)
	if e = audit(ctx, q, c, id, "exchange_rates", "exchange_rates.create", data); e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, gin.H{"id": id})
}
func (s *Service) CreateCurrency(c *gin.Context) {
	var in struct {
		Code       string `json:"code"`
		Name       string `json:"name"`
		MinorUnits int16  `json:"minor_units"`
	}
	if !decode(c, &in) {
		return
	}
	in.Code = strings.ToUpper(strings.TrimSpace(in.Code))
	in.Name = strings.TrimSpace(in.Name)
	if !currencyPattern.MatchString(in.Code) || len(in.Name) == 0 || len(in.Name) > 100 || in.MinorUnits < 0 || in.MinorUnits > 6 {
		fail(c, 400, "Enter a three-letter currency code, name and 0–6 minor units.")
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
	e = q.CreatePurchaseCurrency(ctx, database.CreatePurchaseCurrencyParams{Code: in.Code, Name: in.Name, MinorUnits: in.MinorUnits})
	if e != nil {
		dbError(c, e)
		return
	}
	data, _ := json.Marshal(in)
	if e = audit(ctx, q, c, pgtype.UUID{}, "currencies", "currencies.create", data); e == nil {
		e = tx.Commit(ctx)
	}
	if e != nil {
		dbError(c, e)
		return
	}
	c.JSON(201, in)
}
