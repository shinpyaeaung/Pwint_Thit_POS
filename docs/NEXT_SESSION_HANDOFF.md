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
- Shipment creation/edit records cargo-terminal delivery or collection. POS records customer collection or delivery by us. An optional checkbox enables person/vehicle details. Saved details appear in shipment summaries and invoice snapshots. Missing fulfillment details display as unspecified. Migration 000031 preserves the installed migration checksums and existing recorded values, including delivery defaults previously assigned by migration 000029; it removes that database default for subsequent records.
- Migrations 000029–000031 are additive; generated sqlc bindings are included. No real business records are seeded, reset or converted by tests.
- Verification: `make check`, PostgreSQL integration tests and all 26 real-stack Chromium/WebKit tests pass. Added coverage includes warehouse price validation, exact package damage, delivery persistence, central customer collections, cargo partial payment/history, concurrent overpayment protection, audit-failure rollback, foreign-currency cost settlement, cancelled-charge history and permissions.

Wait for the user's next scope before starting another module.

### Local deployment recovery

The local database already recorded migrations 000029 and 000030 from October 6. Restored 000029 to its exact installed checksum and added 000031 to make missing shipment fulfillment nullable without changing any existing fulfillment values. Never bypass migration checksums or rewrite schema_migrations. `make up` succeeded; the frontend, backend and PostgreSQL are healthy, and http://localhost:8088/api/v1/health reports the database connected. The existing database volume was preserved. PostgreSQL integration tests and all 26 real-stack Chromium/WebKit browser tests were rerun successfully with the full migration chain.

## Landed-cost selling-price workflow

The current user scope replaces price entry during product creation with pricing after landed-cost finalization. Product create/edit forms now define packaging without price inputs; existing saved reference/default prices are preserved for compatibility.

- Warehouse prices and the POS Prices action select a finalized shipment item for that warehouse/product. Purchase, allocated cargo, additional and landed costs display per selected packaging unit and base unit. Costs use the immutable MMK allocations and confirmed sellable quantity; the latest finalized reference is initially selected, with older references available explicitly.
- Enter an individual bottle/piece price or a nonnegative markup on landed cost, separately for retail and wholesale. Both the selected package and base-unit prices save together. Base prices round to four decimal places; package prices multiply that rounded base price by contents. Other warehouses and other packaging units stay unchanged. A 220,000 MMK purchase plus 20,000 MMK cargo per 12-bottle carton yields 240,000/carton and 20,000/bottle; a 5% markup yields 21,000/bottle and 252,000/carton.
- Additive migration 000032 defines finalized cost references and an atomic pricing function. `/pos/pricing-costs` and `/pos/landed-prices` require product update, purchase-cost viewing and landed-cost viewing permissions. Saving revalidates product version, warehouse, packaging and finalized cost source on the server, with exact numeric calculations and atomic price/version/audit writes. Audit records retain the cost source and both saved prices. Existing cost snapshots, batch values, customer special prices and invoice history are preserved.
- No finalized source (including a zero-sellable shipment) means the new pricing form cannot save. Legacy default-price APIs remain compatible with existing callers; the new normal UI uses the landed-cost workflow.

Verification: `make check`, `make test-integration`, and all 28 real-stack Chromium/WebKit browser tests passed. Coverage includes the exact 220,000 + 20,000 MMK / 12-bottle example, direct price and percentage markup, two warehouses with different cargo costs, reload persistence, mobile layout, missing finalized costs, permission denial, stale version rejection and atomic rollback on audit failure. Initial browser test fixtures were corrected to supply shipment dates and expect finalization's 201 status; one existing Safari scroll-tolerance boundary failure passed on the full rerun without changing that test. Mobile pricing screenshot was visually reviewed. Wait for the user's next scope before another module.

Deployment: `make up` succeeded with migration 000032; PostgreSQL, backend and frontend are healthy at http://localhost:8088. Existing database volumes were preserved.

## Transportation fee basis follow-up

The user requested total-shipment or per-carton transportation fees. Add/edit stage now selects the basis, shows a live exact total, and keeps loading/unloading/other charges separate. Per-carton billing stores rate and positive billed count (up to six decimal places); PostgreSQL computes and rounds the transport total to four decimal places. Client-supplied totals cannot override per-carton calculation. The timeline displays the saved rate × count.

Migration 000033 preserves existing amounts by defaulting older stages to TOTAL without rewriting rows. A carton suggestion uses historical purchase carton conversions where available, otherwise configured product carton conversions; if any shipment line has no carton conversion, no partial/invented count is shown. Billed count is confirmed/editable because cargo packaging may differ. Rate and count are saved snapshots, never recomputed when product packaging changes. New fields follow existing cost-view permissions. Existing transaction, version, paid-stage and finalized-cost controls apply. SQL-generated Go bindings are regenerated.

Verification: `make check`, `make test-integration`, and all 28 real-stack Chrome/Safari tests passed. Coverage includes exact fractional carton rates/counts, ignoring client totals in per-carton mode, invalid counts/bases, switching back to total mode, permission filtering, audit rollback, carton suggestions, reload/edit persistence, and unchanged downstream landed-cost totals. The existing authentication test's Users & access link was scoped to the Administration navigation region to avoid ambiguity with the home-page shortcut. `make up` applied migration 000033 successfully; the local app and database are healthy. Existing business records and database volumes were preserved. Wait for the next user scope.

## Arrival-based sellable quantities follow-up

The user requested sellable quantity only after arrival, derived from received minus damaged. Before arrival, shipment costing previews use expected quantities only and expose no received/damaged inputs. After ARRIVED, the form requires actual received and damaged base-unit counts, displays calculated sellable quantity, and sends the counts for server-side exact validation/subtraction. Finalization remains atomic and permission enforced; normalized counts participate in the preview token and immutable costing document. New columns retain the confirmed arrival counts on shipment items with database consistency and arrival-state guards (migration 000034).

Goods receiving prefills those counts and requires exact received/damaged reconciliation for new finalizations, including rejecting different received/damaged counts that happen to produce the same sellable total. Legacy finalized shipments have null arrival-count fields and retain the previous sellable-total reconciliation, with no invented historical counts or snapshot rewrites. Existing batch costs, receipts, rates and movements remain unchanged.

Verification: `make check`, `make test-integration`, and all 28 real-stack Chrome/Safari browser tests passed. Tests cover rejection of pre-arrival actual counts, expected-only planning, server-derived sellable quantity, invalid/damaged/zero/fractional counts, receipt reconciliation, prefills, and the full 55 received − 5 damaged = 50 sellable workflow through inventory and pricing. `make up` completed with migration 000034; frontend, backend and PostgreSQL are healthy, and the local health endpoint reports a connected database. Existing database volumes were preserved. A final check was initially blocked by an approval-review usage limit, then reran successfully when the user resumed. Wait for the next user scope.

## Shipment cartons and pieces display

The user requested carton and piece quantities during shipment creation. Purchase-option and purchase-workflow queries now include the base unit and carton size, preferring the historical carton purchase conversion and otherwise using configured product CARTON packaging. CreateShipment displays both Available and In this shipment as cartons plus loose units, with total individual units in parentheses. Updates follow either base-unit or purchase-package input. Missing carton conversion remains explicitly unknown; no counts are invented. All calculations use fixed-point integers and do not alter stock/allocation writes. Generated SQL bindings are included; no migration is needed.

Verification: `make check`, `make test-integration`, and all 28 real-stack Chrome/Safari tests passed. Browser coverage verifies 40 cartons / 640 bottles in the purchase workspace and 5 cartons + 1 bottle / 61 bottles in standalone shipment creation. The mobile shipment form screenshot was visually reviewed. Wait for the next user scope.

Deployment: `make up` completed successfully; frontend, backend and PostgreSQL are healthy at http://localhost:8088. Existing database records and volumes were preserved.

## Package-based cargo fees and expected quantity

The latest scope replaces carton-specific/total-basis form controls with Package Type, Package Quantity, Fee per Package (MMK), and calculated Total Cargo Fee. Types come from shipment product packaging, including historical purchase conversions. The suggested count is the sum of expected stock divided by the selected conversion, only when every line supports that type; users confirm the cargo bill's actual count. New stages always start with a unit rate. PostgreSQL calculates rate × count exactly, stores both inputs, ignores client totals, and retains separate additional costs. Migration 000035 adds PER_PACKAGE alongside legacy modes without rewriting old rows. Existing total-only stages show their saved amount and require an explicit package rate/count to replace it. Paid/finalized protections, permissions, transactions and audit history remain enforced.

Expected Base Quantity and both shipment-creation entry points display packages with equivalent base-unit counts (including loose pieces). Historical purchase packages take priority; otherwise the largest configured package is displayed. No inventory quantities are changed by these display calculations.

Verification: `make check`, `make test-integration`, and all 28 real-stack Chrome/Safari browser tests passed. Coverage includes 20,000 × 5 = 100,000, PACK billing, fractional quantities and exact rounding, ignoring spoofed totals, invalid counts/types, package rate persistence/editing, cost permission filtering, shipment display and unchanged downstream landed costs. An unrelated supplier pagination dropdown timed out on the first browser run; the full rerun passed. The integration audit-count expectation includes the two new package update assertions.

Deployment: `make up` applied migration 000035 successfully. Frontend, backend and PostgreSQL are healthy; the local health endpoint reports a connected database at http://localhost:8088. Existing records and database volumes were preserved. Wait for the next user scope.

## October 8 scope: warehouse stops and optional POS credit

The user requested multiple warehouse stops/destinations, receiving and selling at an intermediate warehouse, warehouse-to-warehouse movements, and optional credit in POS. They confirmed both full receipt at an intermediate warehouse and splitting goods between intermediate/final warehouses must be possible.

POS implementation: unchecked Sell on Credit checkbox; immediate sales require full payment; credit exposes due date, supports zero/partial payment, and retains customer/credit-limit rules. Blank tender means exact payment normally and zero on credit. Migration 000036 enforces opt-in in the shared server quote/checkout function and snapshots the choice. The nullable Go field preserves legacy request payloads for replay; omitted consent is false for new sales. Existing invoices are unchanged.

Warehouse work is not implemented yet. Current schema has one finalized costing and one posted receipt per shipment, with its single destination determining the receipt warehouse. Multi-stop work must introduce separate per-stop quantity and costing reconciliation, prevent duplicate availability, and preserve existing immutable batch costs, financial allocations and audit history. A warehouse transfer must remove available stock at dispatch and add it only on destination receipt. The user has been asked whether new cargo on A→B transfers increases landed cost at B or is a separate transport expense; that decision is pending. Do not silently choose a financial treatment or claim the warehouse scope is complete.

POS verification: `make check`, `make test-integration`, and all 28 real-stack Chromium/WebKit browser tests passed. Tests cover rejection of unpaid immediate sales in both quote and checkout, checkbox default/toggling, hidden due date, explicit partial-credit checkout and the resulting customer ledger. Existing cash sales, credit limits, below-cost approvals and rollback tests pass.

POS deployment: `make up` applied migration 000036 successfully; local frontend/backend/PostgreSQL are healthy and the API reports a connected database. Existing records and volumes were preserved. Multi-warehouse implementation remains pending the transfer-cost clarification above.
