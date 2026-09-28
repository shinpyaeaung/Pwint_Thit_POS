package reports

import "github.com/gin-gonic/gin"

func (h *Handler) allowed(c *gin.Context, id string) (bool, error) {
	codes, exists := policies[id]
	if !exists || len(codes) == 0 {
		return false, nil
	}
	for _, code := range codes {
		allowed, err := h.authorization.Allowed(c, code)
		if err != nil || !allowed {
			return false, err
		}
	}
	return true, nil
}
func (h *Handler) requireReport(id string) gin.HandlerFunc {
	return func(c *gin.Context) {
		allowed, err := h.allowed(c, id)
		if err != nil {
			reportError(c, 503, "authorization_unavailable", "Report authorization is unavailable.")
			return
		}
		if !allowed {
			reportError(c, 403, "forbidden", "You do not have permission to view this report.")
			return
		}
		c.Next()
	}
}
