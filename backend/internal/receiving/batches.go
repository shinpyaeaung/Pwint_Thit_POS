package receiving

import (
	"github.com/gin-gonic/gin"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

func (s *Service) Batches(c *gin.Context) {
	size, offset, ok := pagination(c)
	if !ok {
		return
	}
	id, ok := optionalID(c, "batch_id")
	if !ok {
		return
	}
	expiry := c.Query("expiry")
	switch expiry {
	case "", "NO_EXPIRY", "EXPIRED", "EXPIRING_30", "EXPIRING_60", "CURRENT":
	default:
		fail(c, 400, "Invalid expiry filter.")
		return
	}
	search := c.Query("q")
	if len(search) > 200 {
		fail(c, 400, "Search is too long.")
		return
	}
	costs, e := s.a.Allowed(c, permissions.FinanceViewLandedCost)
	if e != nil {
		fail(c, 503, "Authorization unavailable.")
		return
	}
	b, e := s.q.ListBatches(c.Request.Context(), database.ListBatchesParams{Search: search, Expiry: expiry, BatchID: id, PageSize: size, PageOffset: offset, Costs: costs})
	response(c, b, e)
}
