# Phase 2 verification

Verified on 2026-09-23 against PostgreSQL 17, using the existing local Colima/Docker server.

## Passed

- Seven migrations apply to an empty disposable database and upgrade the Phase 1 database in place.
- Reapplying is a no-op; changed migration checksums are rejected.
- A deliberately failing migration rolls back its DDL.
- Real database tests reject third roles, invalid role references, negative/NaN financial values, invalid exchange rates, cross-product shipment/batch links, negative stock, excess reservations, invalid damage counts, reversed date ranges, and duplicate usernames.
- Posted purchase lines, posted sale batch costs, finalized batch/shipment costs, exchange-rate history, and audit history resist prohibited changes.
- Exact carton conversions, landed unit cost, shortages, available stock, customer debt, supplier payable, partial payments, return credits, and settlement against historical foreign exchange rates produce expected values.
- Payment direction, customer identity, allocation amount, and historical rate checks reject invalid settlements.
- Go request authorization is exercised against real users, hashed sessions, and permission rows in disposable databases. Missing/forged tokens and role headers do not grant access; Staff Admin grants and revocations take effect; inactive, expired, and revoked sessions fail. Unavailable authorization storage fails closed.
- `make check` passes: Go race-enabled tests, go vet, frontend lint, strict TypeScript, and production frontend build.
- `make test-integration` passes against real PostgreSQL. Test databases are removed afterward; fixture data is never inserted into the application database.
- Application database inspection: **50 tables**, **4 views**, **144 foreign keys**, **246 indexes** (including primary/unique indexes), **39 permissions**, exactly **2 role rows**, **7 migration records**, **0 users**.
- Generated financial/quantity fields use `pgtype.Numeric`; no floating-point financial columns exist.

- Docker rebuild/start passes: migration service exits successfully before the API starts, and all long-running containers are healthy.
- All three Chrome browser tests pass against the migrated Docker/Nginx stack.
- The deployed local `/api/v1/permissions` endpoint returns 401 to an unauthenticated request.

## Scope limits

See [database design](database-design.md) for the explicit database-versus-service enforcement boundary. Login/session issuance, grant-management screens, posting services, transactional stock reconciliation, complete approval workflows, and production credential separation are later slices. No business feature UI or public deployment was added. Changes remain local and uncommitted.
