# Pwint Thit POS 1.2 handoff

## Current scope and baseline

The user supplied the v1.2 redesign scope: one resumable purchase workflow through shipment/transportation/costing/receiving/inventory, optional sections controlled by checkboxes, full Super Admin permissions with explicit accounting/security restrictions, and automatically generated readable business IDs. This scope has been implemented on top of the verified v1.1 baseline. Do not start another business module without new user scope.

- Local app: http://localhost:8088, Docker Compose with the existing PostgreSQL volume.
- Branch: `main`; frontend version: `1.2.0`. Use pnpm and retain the pinned packageManager/lockfile.
- Read `AGENTS.md`, the system specification (including section 70), and `docs/releases/v1.2.md`.
- Light-only appearance remains the preference. Preserve real records, exact amounts, historical rates, batch costs, ledger-based payment statuses, immutable stock movements and finalized costing.

## Implemented behavior

- `/purchases/:id` is the daily workflow workspace. Progress comes from purchase-item allocations, shipment states, finalized costs and posted receipts. All quantities must be allocated and every active linked shipment received before completion.
- Arrange shipment preloads the purchase's remaining goods; partial and consolidated shipments still work. Warehouse creation/edit/archive, shipment editing, transport stages, optional shipment expenses, transit/arrival, landed-cost confirmation and receiving happen in the same workspace.
- Shipment and goods-receipt lists remain available for record history. Original purchase details and financial history expand within the purchase.
- Optional product/supplier/purchase/shipment/transport sections use checkboxes. Collapsing retains existing values rather than silently discarding costs.
- Normal creation forms no longer request product/supplier/purchase/shipment/receipt IDs. All requested IDs have readable type/year sequences, with UUIDs retained internally. Added sales-order/transportation/adjustment/damage/loss references also cover existing rows; preexisting identity columns remain unchanged.
- Server-side Super Admin grants already include all registered permissions. Added open-shipment editing, audited unpaid-stage removal, warehouse editing/archive, and controlled purchase reversals. Paid stages, finalized costs, posted counts/rates and stock/audit history retain intentional restrictions. See the release-note control matrix.
- A purchase can be reversed only without active shipment, payment allocation or supplier return activity. It preserves original amounts/items and records an immutable dated reversal event. Historical payables retain it before that date; purchase/currency reports include equal opposite reversal activity on the reversal date.

## Verification

- `make check` passed: Go race tests/vet, frontend lint and production build.
- `make test-integration` passed against PostgreSQL, including concurrent IDs, transactional counter rollback, import collision reservation, retry-stable IDs, immutable reversals and historical report offsets.
- `make test-e2e` passed: 25 browser tests, with Chromium/WebKit regressions and a new same-purchase-URL workflow through receiving, inventory confirmation, reload, mobile layout and denied staff mutations.
- Tests use disposable databases/accounts; they never seed or reset real app data.
- `make up` rebuilds the running app and applies additive migrations. Git push alone does not update the local app. Never remove database volumes.

## Relevant files

- Database migrations: `000023_workflow_ids.sql`, `000024_purchase_controls.sql`.
- Linked workflow/management queries: `database/queries/workflow.sql`; corresponding generated Go stays committed.
- Purchase workspace: `frontend/src/pages/purchases/PurchaseWorkflow.tsx`.
- Reused inline forms: shipment details/actions/create, goods receiving.
- Reversal report preservation: purchasing backend integration and report purchase/currency/payables queries.
- User guide: `docs/user-guide.md` and `frontend/src/pages/help/guide.ts`.

User authorized committing and pushing verified completed phases to origin. Keep secrets, credentials, local backups, build output and browser artifacts out of Git.
