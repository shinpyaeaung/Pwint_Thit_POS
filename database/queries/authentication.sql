-- name: FindLoginUser :one
SELECT id,username,display_name,password_hash,role_code,is_active FROM app.users WHERE lower(username)=lower($1);
-- name: LockLoginUser :one
SELECT id,password_hash,is_active FROM app.users WHERE id=$1 FOR UPDATE;
-- name: CreateSession :one
INSERT INTO app.user_sessions(user_id,token_hash,created_at,expires_at) VALUES($1,$2,clock_timestamp(),clock_timestamp()+interval '8 hours') RETURNING id;
-- name: RevokeSession :exec
UPDATE app.user_sessions SET revoked_at=clock_timestamp() WHERE token_hash=$1 AND revoked_at IS NULL;
-- name: MarkLogin :exec
UPDATE app.users SET last_login_at=clock_timestamp() WHERE id=$1;
-- name: EffectivePermissions :many
SELECT p.code FROM app.permissions p JOIN app.users u ON u.id=$1
WHERE u.is_active AND (u.role_code='SUPER_ADMIN' OR EXISTS(SELECT 1 FROM app.user_permissions up WHERE up.user_id=u.id AND up.permission_code=p.code)) ORDER BY p.code;
-- name: ConsumeLoginAttempt :one
INSERT INTO app.login_throttles(key_hash,attempts) VALUES($1,1)
ON CONFLICT(key_hash) DO UPDATE SET
 attempts=CASE WHEN app.login_throttles.window_started_at<now()-interval '15 minutes' THEN 1 ELSE least(app.login_throttles.attempts+1,10000) END,
 window_started_at=CASE WHEN app.login_throttles.window_started_at<now()-interval '15 minutes' THEN now() ELSE app.login_throttles.window_started_at END
RETURNING attempts;
-- name: PruneLoginAttempts :exec
DELETE FROM app.login_throttles WHERE window_started_at<now()-interval '1 day';
-- name: RecordAuthAudit :exec
INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,reason) VALUES($1,$2,'users',$3,$4);
-- name: ListUsers :many
SELECT id,username,display_name,role_code,is_active FROM app.users ORDER BY lower(username);
-- name: CreateUser :one
INSERT INTO app.users(username,display_name,password_hash,role_code) VALUES($1,$2,$3,$4) RETURNING id;
-- name: FindUser :one
SELECT id,username,display_name,role_code,is_active FROM app.users WHERE id=$1 FOR UPDATE;
-- name: ClearUserPermissions :exec
DELETE FROM app.user_permissions WHERE user_id=$1;
-- name: GrantPermission :exec
INSERT INTO app.user_permissions(user_id,permission_code,granted_by) VALUES($1,$2,$3);
