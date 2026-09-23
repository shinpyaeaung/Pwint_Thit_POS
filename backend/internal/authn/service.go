package authn

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/authz"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/password"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"
)

type DB interface {
	database.DBTX
	Begin(context.Context) (pgx.Tx, error)
}
type Options struct {
	SecureCookie   bool
	AllowedOrigins []string
}
type Service struct {
	db      DB
	q       *database.Queries
	options Options
	hashing chan struct{}
}

func New(db DB, options Options) *Service {
	return &Service{db: db, q: database.New(db), options: options, hashing: make(chan struct{}, 4)}
}

var usernamePattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._-]{2,99}$`)

func ValidUsername(s string) bool { return usernamePattern.MatchString(s) }

func (s *Service) SameOrigin() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.Method == http.MethodGet || c.Request.Method == http.MethodHead || c.Request.Method == http.MethodOptions {
			c.Next()
			return
		}
		if s == nil {
			fail(c, 503, "authentication_unavailable", "Authentication is unavailable.")
			return
		}
		allowed := false
		for _, origin := range s.options.AllowedOrigins {
			if c.GetHeader("Origin") == origin {
				allowed = true
				break
			}
		}
		if !allowed || c.GetHeader("X-Pwint-Thit-Request") != "1" {
			fail(c, 403, "invalid_origin", "The request origin is not allowed.")
			return
		}
		c.Next()
	}
}
func decode(c *gin.Context, value any) bool {
	if !strings.HasPrefix(c.ContentType(), "application/json") {
		fail(c, 415, "invalid_content_type", "Send a JSON request.")
		return false
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 16*1024)
	dec := json.NewDecoder(c.Request.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(value); err != nil {
		fail(c, 400, "invalid_request", "Check the request fields.")
		return false
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		fail(c, 400, "invalid_request", "Send one JSON object.")
		return false
	}
	return true
}
func (s *Service) Login(c *gin.Context) {
	var input struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !decode(c, &input) {
		return
	}
	input.Username = strings.TrimSpace(input.Username)
	if !ValidUsername(input.Username) || len(input.Password) > 128 {
		fail(c, 401, "invalid_credentials", "Invalid username or password.")
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()
	if err := s.q.PruneLoginAttempts(ctx); err != nil {
		unavailable(c)
		return
	}
	for _, limit := range []struct {
		key string
		max int32
	}{{"ip:" + c.ClientIP(), 60}, {"user:" + strings.ToLower(input.Username), 10}} {
		hash := sha256.Sum256([]byte(limit.key))
		count, err := s.q.ConsumeLoginAttempt(ctx, hash[:])
		if err != nil {
			unavailable(c)
			return
		}
		if count > limit.max {
			c.Header("Retry-After", "900")
			fail(c, 429, "too_many_attempts", "Too many sign-in attempts. Try again in 15 minutes.")
			return
		}
	}
	select {
	case s.hashing <- struct{}{}:
		defer func() { <-s.hashing }()
	default:
		fail(c, 429, "busy", "Please try again shortly.")
		return
	}
	user, err := s.q.FindLoginUser(ctx, input.Username)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		unavailable(c)
		return
	}
	hash := user.PasswordHash
	if err != nil || !user.IsActive {
		hash = password.DummyHash
	}
	valid := password.Verify(input.Password, hash)
	if !valid || err != nil || !user.IsActive {
		fail(c, 401, "invalid_credentials", "Invalid username or password.")
		return
	}
	raw := make([]byte, 32)
	if _, err = rand.Read(raw); err != nil {
		unavailable(c)
		return
	}
	token := base64.RawURLEncoding.EncodeToString(raw)
	tokenHash := sha256.Sum256([]byte(token))
	tx, err := s.db.Begin(ctx)
	if err != nil {
		unavailable(c)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	locked, err := q.LockLoginUser(ctx, user.ID)
	if err != nil {
		unavailable(c)
		return
	}
	if !locked.IsActive || locked.PasswordHash != user.PasswordHash {
		fail(c, 401, "invalid_credentials", "Invalid username or password.")
		return
	}
	if old := authz.Token(c); old != "" {
		h := sha256.Sum256([]byte(old))
		if err = q.RevokeSession(ctx, h[:]); err != nil {
			unavailable(c)
			return
		}
	}
	if _, err = q.CreateSession(ctx, database.CreateSessionParams{UserID: user.ID, TokenHash: tokenHash[:]}); err != nil {
		unavailable(c)
		return
	}
	if err = q.MarkLogin(ctx, user.ID); err != nil {
		unavailable(c)
		return
	}
	if err = audit(ctx, q, user.ID, user.ID, "auth.login", "Session created"); err != nil {
		unavailable(c)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		unavailable(c)
		return
	}
	s.cookie(c, token, 8*60*60)
	c.JSON(200, gin.H{"message": "Signed in."})
}
func (s *Service) Logout(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	if token := authz.Token(c); token != "" {
		hash := sha256.Sum256([]byte(token))
		tx, err := s.db.Begin(ctx)
		if err != nil {
			unavailable(c)
			return
		}
		defer tx.Rollback(context.Background())
		q := s.q.WithTx(tx)
		user, lookup := q.AuthenticateSession(ctx, hash[:])
		if lookup != nil && !errors.Is(lookup, pgx.ErrNoRows) {
			unavailable(c)
			return
		}
		if err = q.RevokeSession(ctx, hash[:]); err != nil {
			unavailable(c)
			return
		}
		if lookup == nil {
			if err = audit(ctx, q, user.ID, user.ID, "auth.logout", "Session revoked"); err != nil {
				unavailable(c)
				return
			}
		}
		if err = tx.Commit(ctx); err != nil {
			unavailable(c)
			return
		}
	}
	s.cookie(c, "", -1)
	c.Status(http.StatusNoContent)
}
func (s *Service) cookie(c *gin.Context, value string, age int) {
	expires := time.Now().Add(8 * time.Hour)
	if age < 0 {
		expires = time.Unix(1, 0)
	}
	http.SetCookie(c.Writer, &http.Cookie{Name: authz.CookieName, Value: value, Path: "/api/v1", MaxAge: age, Expires: expires, HttpOnly: true, Secure: s.options.SecureCookie, SameSite: http.SameSiteStrictMode})
}
func (s *Service) Current(c *gin.Context) {
	user, ok := authz.Principal(c)
	if !ok {
		fail(c, 401, "unauthorized", "Sign in to continue.")
		return
	}
	codes, err := s.q.EffectivePermissions(c.Request.Context(), user.ID)
	if err != nil {
		unavailable(c)
		return
	}
	if codes == nil {
		codes = []string{}
	}
	c.JSON(200, gin.H{"user": gin.H{"id": user.ID, "username": user.Username, "display_name": user.DisplayName, "role": user.RoleCode, "permissions": codes}})
}
func (s *Service) Users(c *gin.Context) {
	rows, err := s.q.ListUsers(c.Request.Context())
	if err != nil {
		unavailable(c)
		return
	}
	users := make([]gin.H, 0, len(rows))
	for _, u := range rows {
		users = append(users, gin.H{"id": u.ID, "username": u.Username, "display_name": u.DisplayName, "role": u.RoleCode, "active": u.IsActive})
	}
	c.JSON(200, gin.H{"users": users})
}
func (s *Service) CreateStaff(c *gin.Context) {
	var in struct {
		Username    string `json:"username"`
		DisplayName string `json:"display_name"`
		Password    string `json:"password"`
	}
	if !decode(c, &in) {
		return
	}
	in.Username = strings.TrimSpace(in.Username)
	in.DisplayName = strings.TrimSpace(in.DisplayName)
	if !ValidUsername(in.Username) || len(in.DisplayName) == 0 || len(in.DisplayName) > 200 {
		fail(c, 400, "invalid_user", "Enter a valid username and display name.")
		return
	}
	select {
	case s.hashing <- struct{}{}:
		defer func() { <-s.hashing }()
	default:
		fail(c, 429, "busy", "Please try again shortly.")
		return
	}
	hash, err := password.Hash(in.Password)
	if err != nil {
		fail(c, 400, "invalid_password", "Use at least 12 characters and at most 128 bytes.")
		return
	}
	ctx := c.Request.Context()
	tx, err := s.db.Begin(ctx)
	if err != nil {
		unavailable(c)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	id, err := q.CreateUser(ctx, database.CreateUserParams{Username: in.Username, DisplayName: in.DisplayName, PasswordHash: hash, RoleCode: permissions.StaffAdmin})
	if err != nil {
		var pe *pgconn.PgError
		if errors.As(err, &pe) && pe.Code == "23505" {
			fail(c, 409, "username_exists", "That username is already in use.")
			return
		}
		unavailable(c)
		return
	}
	actor, _ := authz.Principal(c)
	if err = audit(ctx, q, actor.ID, id, "users.create", "Staff Admin created with no permissions"); err != nil {
		unavailable(c)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		unavailable(c)
		return
	}
	c.JSON(201, gin.H{"id": id})
}
func (s *Service) UserPermissions(c *gin.Context) {
	var id pgtype.UUID
	if err := id.Scan(c.Param("id")); err != nil {
		fail(c, 400, "invalid_user", "Invalid user ID.")
		return
	}
	_, err := s.q.FindUser(c.Request.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		fail(c, 404, "not_found", "User not found.")
		return
	}
	if err != nil {
		unavailable(c)
		return
	}
	codes, err := s.q.EffectivePermissions(c.Request.Context(), id)
	if err != nil {
		unavailable(c)
		return
	}
	if codes == nil {
		codes = []string{}
	}
	c.JSON(200, gin.H{"permissions": codes})
}
func (s *Service) SetPermissions(c *gin.Context) {
	var id pgtype.UUID
	if err := id.Scan(c.Param("id")); err != nil {
		fail(c, 400, "invalid_user", "Invalid user ID.")
		return
	}
	var input struct {
		Permissions []string `json:"permissions"`
	}
	if !decode(c, &input) {
		return
	}
	if input.Permissions == nil {
		fail(c, 400, "invalid_permissions", "Supply a permissions array, including an empty array to revoke all.")
		return
	}
	ctx := c.Request.Context()
	tx, err := s.db.Begin(ctx)
	if err != nil {
		unavailable(c)
		return
	}
	defer tx.Rollback(context.Background())
	q := s.q.WithTx(tx)
	target, err := q.FindUser(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		fail(c, 404, "not_found", "User not found.")
		return
	}
	if err != nil {
		unavailable(c)
		return
	}
	if target.RoleCode != permissions.StaffAdmin {
		fail(c, 400, "fixed_permissions", "Super Admin access cannot be restricted.")
		return
	}
	catalog, err := q.ListPermissions(ctx)
	if err != nil {
		unavailable(c)
		return
	}
	known := map[string]bool{}
	for _, p := range catalog {
		known[p.Code] = true
	}
	seen := map[string]bool{}
	for _, code := range input.Permissions {
		if !known[code] || seen[code] {
			fail(c, 400, "invalid_permissions", "Unknown or duplicate permission.")
			return
		}
		seen[code] = true
	}
	before, err := q.EffectivePermissions(ctx, id)
	if err != nil {
		unavailable(c)
		return
	}
	if err = q.ClearUserPermissions(ctx, id); err != nil {
		unavailable(c)
		return
	}
	actor, _ := authz.Principal(c)
	for _, code := range input.Permissions {
		if err = q.GrantPermission(ctx, database.GrantPermissionParams{UserID: id, PermissionCode: code, GrantedBy: actor.ID}); err != nil {
			unavailable(c)
			return
		}
	}
	change, _ := json.Marshal(map[string]any{"before": before, "after": input.Permissions})
	if err = audit(ctx, q, actor.ID, id, "permissions.replace", string(change)); err != nil {
		unavailable(c)
		return
	}
	if err = tx.Commit(ctx); err != nil {
		unavailable(c)
		return
	}
	c.Status(204)
}
func audit(ctx context.Context, q *database.Queries, actor, target pgtype.UUID, action, reason string) error {
	return q.RecordAuthAudit(ctx, database.RecordAuthAuditParams{ActorID: actor, EntityID: target, Action: action, Reason: pgtype.Text{String: reason, Valid: true}})
}
func unavailable(c *gin.Context) {
	fail(c, 503, "authentication_unavailable", "The service is unavailable. Please try again.")
}
func fail(c *gin.Context, status int, code, message string) {
	c.AbortWithStatusJSON(status, gin.H{"error": gin.H{"code": code, "message": message, "request_id": c.GetString("request_id")}})
}
