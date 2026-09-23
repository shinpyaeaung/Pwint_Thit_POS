-- name: AuthenticateSession :one
SELECT u.id, u.role_code, u.username, u.display_name
FROM app.user_sessions s JOIN app.users u ON u.id=s.user_id
WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now()
  AND s.created_at>=u.password_changed_at AND u.is_active;

-- name: HasPermission :one
SELECT EXISTS (
 SELECT 1 FROM app.users u CROSS JOIN app.permissions p
 WHERE u.id=$1 AND p.code=$2 AND u.is_active
 AND (u.role_code='SUPER_ADMIN' OR EXISTS (
   SELECT 1 FROM app.user_permissions up WHERE up.user_id=u.id AND up.permission_code=p.code
 ))
)::boolean;

-- name: ListPermissions :many
SELECT code,description,is_sensitive FROM app.permissions ORDER BY code;
