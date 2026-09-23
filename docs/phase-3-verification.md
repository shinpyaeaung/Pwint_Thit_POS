# Phase 3 verification

Verified on 2026-09-23:

- `make check`: Go race tests and vet; frontend lint and production build passed.
- `make test-integration`: real PostgreSQL schema and authorization/authentication tests passed, including session expiry/revocation, inactive/password-changed users, hash-only token persistence, grants/revocations, denied escalation, transaction rollback, audits, and login throttling.
- `make test-e2e`: eight Chrome tests passed against isolated Go/Vite/PostgreSQL. Verified protected-page redirects, bad credentials, session restoration, HttpOnly cookie behavior, logout, Staff Admin denial, account creation, grant/revoke UI and immediate backend enforcement, health recovery, and mobile width.
- Login mobile and users desktop screenshots reviewed.

All database fixtures are disposable. No application user or password is seeded. Bootstrap the first Super Admin with `make create-admin`. Password reset and business features are outside Phase 3.

- `make up`: migration 000008 applied; rebuilt PostgreSQL/API/frontend stack healthy. Docker `/login` and health returned 200; unauthenticated current-user/users returned 401; login without Origin returned 403.
- Container bootstrap command created the first owner and rejected a repeat in a temporary database, which was removed afterward.
