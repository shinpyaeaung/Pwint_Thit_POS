# Phase 3 — Authentication and permissions

The only roles are `SUPER_ADMIN` (full access) and `STAFF_ADMIN` (explicit database grants). Staff accounts start with no grants. Go checks the current grants on every protected request; changes take effect without issuing a new session. Frontend navigation and route checks mirror these controls.

## First account

Run `make db-up`, then `make create-admin`. The command applies migrations and prompts privately for a password (minimum 12 characters, maximum 128 UTF-8 bytes). The default username is `admin`. To customize it, run from `backend`: `go run ./cmd/create-admin --username owner --name 'Owner'` after migrating.

For the running container stack use `docker-compose exec backend ./create-admin --username owner --name 'Owner'`. Bootstrap refuses if any Super Admin already exists. No application account or default password is seeded. Test accounts only exist in disposable test databases.

## Session security

Passwords use salted Argon2id (19 MiB, two iterations, one lane). Login creates a random 256-bit opaque session token; PostgreSQL stores only its SHA-256 digest. The browser receives an HttpOnly, SameSite=Strict cookie scoped to `/api/v1`. Sessions expire after eight hours; logout revokes them server-side and clears the cookie. Password changes and inactive accounts invalidate authentication. Login rotates the current browser session. Tokens are never stored in localStorage or returned in JSON.

`APP_ENV=production` enables Secure cookies and requires explicit HTTPS `ALLOWED_ORIGINS`, comma-separated without trailing slashes. Serve the frontend and `/api` on the same HTTPS origin. Unsafe requests require a matching Origin and `X-Pwint-Thit-Request: 1`; the frontend adds the header automatically. No cross-origin API access is enabled. The development origins cover localhost/127.0.0.1 on 5173 and 8088.

Login throttles persist in PostgreSQL: 10 attempts per normalized username and 60 per connection IP in 15 minutes, including successful attempts. Argon2 work is bounded to four concurrent operations per API process. Behind the current proxy the IP limit is shared because forwarded client IP headers are deliberately untrusted. Redis is not required.

## API

| Method/path (under `/api/v1`) | Access |
| --- | --- |
| POST `/auth/login` | Username/password; origin protection |
| POST `/auth/logout` | Idempotent session revocation; origin protection |
| GET `/auth/me` | Active session; public user fields and effective permissions |
| GET `/users` | `users.manage` |
| POST `/users` | `users.manage`; creates Staff Admin with no grants |
| GET `/permissions` | `permissions.manage` |
| GET/PUT `/users/:id/permissions` | Super Admin only; PUT replaces the complete grant list |

Permission assignment is owner-only, preventing delegated user managers from granting themselves more access. Super Admin full access cannot be restricted. Unknown/duplicate permission codes are rejected. User creation, grant replacement, login, and logout are audited transactionally. Password hashes/session tokens never appear in user responses or audit data.

## Extending business modules

Go permission constants are centralized in `backend/internal/permissions`; reusable middleware lives in `backend/internal/authz`. Attach `authorization.Require(permissions.ProductsCreate)` at route registration. Do not duplicate permission checks in individual handlers. Sensitive response fields and their query paths will need the corresponding centralized checks when their business modules are implemented.

Migration 000008 adds the requested granular product, purchase, sale-discount, finance, and report codes. Existing legacy codes remain intact; existing relevant grants are copied during migration. This is a one-time compatibility upgrade, not a permanent alias relationship. The frontend catalog is loaded from PostgreSQL; frontend route codes are centralized in `frontend/src/permissions`.

Password reset/recovery, MFA, and business APIs are outside this slice. There is no public self-registration.

## Verification

`make check` runs Go race tests/vet plus frontend lint/build. `make test-integration` validates PostgreSQL-backed authentication, expiry, revocation, role enforcement, grant updates, audit records, and throttling. `make test-e2e` starts a disposable full stack and tests the browser flows; it does not modify application users.
