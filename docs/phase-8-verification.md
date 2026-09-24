# Phase 8 verification

Verified on 2026-09-24:

- `make generate`: shipment queries generated with pinned sqlc; generated models and query interface are committed.
- `make check`: Go race tests and vet, pnpm frontend lint, TypeScript and production build passed. Vite retains the existing shared-bundle size advisory; the shipment page is lazy-loaded separately.
- `make test-integration`: all real PostgreSQL suites passed. Shipment coverage includes 25 stages and pagination; exact transport sums and foreign-expense conversion; voids excluded from totals; transaction rollback; duplicate requests; stale versions; invalid dates/NaN; posted-payment status and allocated-stage protection; backend permissions and cost omission; valid status transitions; concurrent purchase allocation; cancelled allocation release; closed/finalized mutation rejection; and audit records.
- `make test-e2e`: all 14 Chromium tests passed. The shipment workflow creates supplier/product/purchase fixtures, creates a warehouse and shipment, adds stages, edits a fee, adds a foreign-currency expense, voids with a reason, marks departure and arrival, searches shipments, and checks staff API/UI restrictions.
- Desktop shipment details and 375px creation/details screenshots were visually reviewed. Mobile width checks passed. The browser test exposed and verified a fix for Radix's transient empty form value when asynchronous warehouse options change.

- `make up`: applied migration 000012 and rebuilt the local stack. PostgreSQL, backend and frontend are healthy. Deployed smoke checks passed for health, admin login/logout, shipments, warehouse/purchase choices, currencies and the frontend route; unauthenticated shipment reads returned 401.

Test fixtures use disposable databases, never the application's business database. Payment entry, receiving, inventory updates and landed-cost allocation remain for their requested phases. Shipment payment status uses posted ledger allocations.
