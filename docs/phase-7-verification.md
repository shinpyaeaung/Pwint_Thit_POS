# Phase 7 verification

Verified on 2026-09-24:

- `make generate`: purchasing/currency/reference queries generated with the pinned sqlc version.
- `make check`: Go race tests/vet, frontend lint, TypeScript and production build passed.
- `make test-integration`: all PostgreSQL suites passed. Purchasing coverage includes January 25/March 27 historical preservation; 10,000 INR → 250,000 MMK; exact fractional rounding; fixed MMK rate; rejected NaN/excess precision/future or mismatched quotes; active references and stale packaging; transaction rollback; cost-field omission; custom-rate permission checks; currencies; filters/pagination; immutable posted headers/items/amount snapshots; audit writes; sequential and concurrent idempotent retries; and balances after a partial payment using the historical rate.
- `make test-e2e`: all 13 Chrome tests passed. The new workflow records a historical quote, creates a carton purchase, verifies exact fractional and 10,000 INR/250,000 MMK previews, confirms posting, reads item quantities and details, adds a later quote without changing the earlier purchase, checks supplier balances and history links, searches purchases, and verifies read-only staff cannot obtain costs or create purchases.
- `make up`: rebuilt the application and applied migration 000011 with all services healthy. Deployed smoke checks passed for health, login/logout, purchase list, all five currencies, rate reads, supplier/product choices and the frontend route. Unauthenticated purchase access returned 401.
- Desktop Purchase Details and the 375px Create Purchase form were visually reviewed. Mobile width assertion passed after correcting the supplier selector's grid sizing.

Automated fixtures run only in disposable databases. No demonstration purchases, rates, payments or suppliers are inserted in the application's database. Payment entry, stock receiving, landed costs, and reversal entry are not implemented in this phase; existing ledger records are used for supplier balances.
