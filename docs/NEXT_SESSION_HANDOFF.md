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
- Receive Goods uses a wide desktop dialog with responsive product cards, separate quantity/batch sections and prominent received/missing/sellable totals. Other edit dialogs retain their compact size.
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

## Packaging, shipments and supplier payments follow-up

The user supplied `Pwint_Thit_POS_Packaging_Shipment_Payment_Requirements.md`. See `docs/packaging-shipment-payments.md` for the implementation review and business decisions. The user explicitly confirmed supplier invoice debts and transport-provider debts must remain separate.

- Product forms expose purchase packaging, per-product contents, reference purchase prices in MMK and independent retail/wholesale prices for each unit. Purchase defaults and reference cost previews never replace historical purchases or landed batch costs.
- Purchase workspace includes package allocation totals; shipment entry can accept package counts. Existing split/consolidated shipment and multi-leg costing integrity is retained.
- POS supports carton and bottle lines together, reserving quoted FIFO quantities across lines.
- `/supplier-payments` and purchase details provide partial/full supplier payments, histories, method setup, filtering and balances. Transactions serialize against the purchase and deduplicate retries; payment, allocation and audit writes commit together. Payments currently settle in the purchase currency at its historical rate. No supplier advance or cross-currency settlement feature is implied.
- Additive migrations 000025–000028; sqlc-generated query files are committed. Existing financial/stock data is preserved.
- Verification includes `make check`, PostgreSQL integration tests (concurrent overpayment, retry deduplication, audit-failure rollback, immutable payment history, independent prices and mixed-unit FIFO), and 26 real-stack Chromium/WebKit browser tests. The browser suite covers 80 cartons × 16 bottles, two 40-carton shipments, rejected excess allocation, partial/full payments and completed mixed-unit sales.

Wait for the next user scope before adding another module. The v1.2 controls above continue to apply.

## October 6 continuation verification

Re-reviewed the original packaging/shipment/payment requirements after the interrupted session. The implementation was already in local commit `0ebc0a4`; no duplicate feature implementation was needed. Requirement coverage and accounting boundaries are recorded in `docs/packaging-shipment-payments.md`.

Fresh verification passed: `make check`, `make test-integration`, and all 26 real-stack browser tests from `make test-e2e`. Started the existing Colima runtime and rebuilt/started the local app with `make up`; migration exited successfully and PostgreSQL, backend and frontend are healthy at http://localhost:8088. Existing database volume was preserved. Initial test attempts were blocked by a stopped runtime and sandbox network access; the authorized reruns passed.

## October 7: central payments, warehouse pricing and delivery follow-up

The user's six-part scope is implemented. See `docs/distribution-payments-warehouse-pricing.md` for business rules and screen locations.

- Product creation explains that packaging defines future purchase/sale units and does not create stock. Existing packaging is retained.
- `/payments` centrally manages supplier payments, customer invoice collections, cargo-terminal payments and separate shipment-cost settlements. Categories and mutations enforce existing backend permissions. Cargo payments use the immutable ledger, historical rates, request deduplication, shipment locking and atomic payment/allocation/audit transactions. Cancelled shipment charges remain visible with their status; cancellation does not erase financial history.
- `/warehouse-prices` and POS's Prices button configure independent retail/wholesale prices for each warehouse/product/unit, including cartons and individual units. Priority: customer special price, warehouse price, product default. Existing invoices and batch costs are unchanged.
- Stock issue entry accepts configured cartons or individual units, previews affected stock, and converts on the server before immutable movement posting. Mixed-unit FIFO sales remain supported.
- Shipment creation/edit records cargo-terminal delivery or collection. POS records customer collection or delivery by us. An optional checkbox enables person/vehicle details. Saved details appear in shipment summaries and invoice snapshots. Older records remain unspecified rather than receiving invented historical details.
- Migrations 000029–000030 are additive; generated sqlc bindings are included. No real business records are seeded, reset or converted by tests.
- Verification: `make check`, PostgreSQL integration tests and all 26 real-stack Chromium/WebKit tests pass. Added coverage includes warehouse price validation, exact package damage, delivery persistence, central customer collections, cargo partial payment/history, concurrent overpayment protection, audit-failure rollback, foreign-currency cost settlement, cancelled-charge history and permissions.

Wait for the user's next scope before starting another module.
