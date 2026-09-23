# Phase 6 verification

Verified on 2026-09-23:

- `make generate`: supplier sqlc queries generated successfully.
- `make check`: Go race tests, vet, frontend lint, TypeScript and production build passed.
- `make test-integration`: PostgreSQL migrations and all existing suites passed. Supplier tests cover contacts, country normalization, input validation, duplicate codes, search/filters, pagination, stale writes, missing records, archive preservation, before/after audit writes and denied staff mutations. Purchase history is isolated by supplier and preserves exact decimal totals; costs are omitted without the cost-view grant, even when purchase-view access is present.
- `make test-e2e`: all 12 Chrome tests passed. The supplier workflow creates, reads, edits, searches, filters, paginates and archives suppliers; verifies real purchase history and pagination; and exercises a read-only staff account's UI and direct API access. Existing authentication, design-system and product workflows also passed.
- `make up`: built both application images and applied migration 000010 with all three services healthy. Local smoke checks passed for health, login/logout, supplier list, permission catalog, existing products and the supplier frontend route; unauthenticated supplier access returned 401.
- Reviewed desktop supplier details/history and the 375px supplier list. No horizontal page overflow.
- Corrected an existing browser-test wait: a permissions drawer becomes hidden behind the confirmation dialog before the save completes, so revocation assertions now wait for the saving dialog to close.

Test suppliers, products, purchases and users exist only in disposable test databases. No demonstration suppliers or purchases are inserted in the application database. Purchase creation and supplier payable workflows remain outside this phase.
