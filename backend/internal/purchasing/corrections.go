package purchasing

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
)

func (s *Service) Correct(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	var in struct {
		Version  string `json:"version"`
		Reason   string `json:"reason"`
		Purchase Input  `json:"purchase"`
	}
	if !decode(c, &in) {
		return
	}
	in.Reason = strings.TrimSpace(in.Reason)
	if in.Reason == "" || len(in.Reason) > 2000 || !decimal(in.Version, 14, 0, false) {
		fail(c, 400, "Enter a correction reason and the current purchase revision.")
		return
	}
	if message := in.Purchase.validate(); message != "" {
		fail(c, 400, message)
		return
	}
	actor, _ := authz.Principal(c)
	data, _ := json.Marshal(in)
	_, e := s.q.CorrectPurchase(c.Request.Context(), database.CorrectPurchaseParams{PurchaseID: id, Actor: actor.ID, Data: data})
	if e != nil {
		var pe *pgconn.PgError
		if errors.As(e, &pe) && strings.HasPrefix(pe.Message, "correction: ") {
			status := 409
			if pe.Code == "42501" {
				status = 403
			}
			fail(c, status, strings.TrimPrefix(pe.Message, "correction: "))
			return
		}
		dbError(c, e)
		return
	}
	result, e := s.q.GetPurchaseDocument(c.Request.Context(), database.GetPurchaseDocumentParams{ID: id, Costs: true})
	respond(c, result, e)
}
func (s *Service) CorrectionHistory(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	data, e := s.q.PurchaseCorrectionHistory(c.Request.Context(), id)
	respond(c, data, e)
}
