package products

import (
	"context"
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"strings"
)

func (s *Service) SaveLookup(kind string) gin.HandlerFunc {
	return func(c *gin.Context) {
		var in struct {
			Name     string `json:"name"`
			IsActive *bool  `json:"is_active"`
		}
		if !decode(c, &in) {
			return
		}
		in.Name = strings.TrimSpace(in.Name)
		if in.Name == "" || len(in.Name) > 100 {
			fail(c, 400, "Enter a name of up to 100 bytes.")
			return
		}
		update := c.Param("id") != ""
		var id pgtype.UUID
		if update {
			var ok bool
			id, ok = pathID(c)
			if !ok {
				return
			}
			if in.IsActive == nil {
				fail(c, 400, "Supply active status.")
				return
			}
		}
		ctx := c.Request.Context()
		tx, err := s.db.Begin(ctx)
		if err != nil {
			dbError(c, err)
			return
		}
		defer tx.Rollback(context.Background())
		q := s.q.WithTx(tx)
		var before []byte
		var name string
		var active bool
		if kind == "categories" {
			if update {
				old, e := q.LockCategory(ctx, id)
				err = e
				before, _ = json.Marshal(gin.H{"id": old.ID, "name": old.Name, "is_active": old.IsActive})
				if err == nil {
					v, e := q.UpdateCategory(ctx, database.UpdateCategoryParams{ID: id, Name: in.Name, IsActive: *in.IsActive})
					err = e
					name = v.Name
					active = v.IsActive
				}
			} else {
				v, e := q.CreateCategory(ctx, in.Name)
				err = e
				id = v.ID
				name = v.Name
				active = v.IsActive
			}
		} else {
			if update {
				old, e := q.LockBrand(ctx, id)
				err = e
				before, _ = json.Marshal(gin.H{"id": old.ID, "name": old.Name, "is_active": old.IsActive})
				if err == nil {
					v, e := q.UpdateBrand(ctx, database.UpdateBrandParams{ID: id, Name: in.Name, IsActive: *in.IsActive})
					err = e
					name = v.Name
					active = v.IsActive
				}
			} else {
				v, e := q.CreateBrand(ctx, in.Name)
				err = e
				id = v.ID
				name = v.Name
				active = v.IsActive
			}
		}
		if err != nil {
			dbError(c, err)
			return
		}
		after, _ := json.Marshal(gin.H{"id": id, "name": name, "is_active": active})
		action := kind + ".create"
		status := 201
		if update {
			action = kind + ".update"
			status = 200
		}
		if err = audit(ctx, q, c, id, kind, action, before, after); err == nil {
			err = tx.Commit(ctx)
		}
		if err != nil {
			dbError(c, err)
			return
		}
		c.Data(status, "application/json", after)
	}
}
func (s *Service) CreateUnit(c *gin.Context) {
	var in struct {
		Code string `json:"code"`
		Name string `json:"name"`
	}
	if !decode(c, &in) {
		return
	}
	in.Code = strings.ToUpper(strings.TrimSpace(in.Code))
	in.Name = strings.TrimSpace(in.Name)
	if !codePattern.MatchString(in.Code) || in.Name == "" || len(in.Name) > 100 {
		fail(c, 400, "Enter an uppercase unit code (up to 20 letters/digits/underscores) and name.")
		return
	}
	ctx := c.Request.Context()
	tx, err := s.db.Begin(ctx)
	if err != nil {
		dbError(c, err)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	v, err := q.CreateCatalogUnit(ctx, database.CreateCatalogUnitParams{Code: in.Code, Name: in.Name})
	if err != nil {
		dbError(c, err)
		return
	}
	after, _ := json.Marshal(gin.H{"code": v.Code, "name": v.Name})
	if err = audit(ctx, q, c, pgtype.UUID{}, "units", "units.create", nil, after); err == nil {
		err = tx.Commit(ctx)
	}
	if err != nil {
		dbError(c, err)
		return
	}
	c.Data(201, "application/json", after)
}
