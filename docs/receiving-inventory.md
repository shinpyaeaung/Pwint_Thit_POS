# Goods receiving and inventory — Phase 11

Open **Goods receiving** to post an arrived shipment, or use **Receive goods** on its details page. Open **Inventory** for batch stock and **Stock movements** for its history. Product details also links to filtered batch stock.

## Receiving workflow

1. Count physical goods and confirm their sellable quantity in the shipment's landed-cost workflow before finalizing costs.
2. Choose an arrived shipment with finalized landed costs. Enter a receipt number and receiving date, then count every shipment item.
3. Enter received cartons and individual units. Received quantity includes damaged units. Each item needs a batch number; expiry is required for products configured to track expiry.
4. Explain missing or damaged quantities, review and post.

Calculations use exact PostgreSQL NUMERIC and decimal strings; the frontend preview uses scaled integers:

- Received = cartons × snapshotted carton size + individual units.
- Missing = expected − received.
- Sellable = received − damaged.
- Available = sellable stock − reserved stock.

A receipt covers the whole shipment exactly once. Partial/multiple receipts and receipt reversals are not exposed in this phase. Over-receiving, excessive damage, stale carton conversions and discrepancies against finalized sellable quantities are rejected. Finalized historical costs are never silently recalculated. If finalized counts are wrong, posting stops; an authorized costing correction workflow is required rather than editing the snapshot.

Posting creates the receipt, receipt items, finalized batches, receipt movements and audit record in one database transaction, and marks the shipment RECEIVED. Batch costs copy the entire allocated purchase, transportation and expense amounts from finalized shipment items. Missing/damaged acquisition losses are already reflected by dividing those costs by sellable quantity, so receiving does not post a second financial loss entry.

Wholly missing goods retain a zero-sellable batch and its full costs, with no stock movement because nothing entered stock. Wholly damaged goods enter only damaged stock. Their unit cost remains NULL, not a fabricated zero; sellable adjustments are prohibited for such batches.

## Inventory controls

Stock is stored in base units per warehouse and batch. Carton equivalents use the conversion captured at receipt time. Inventory displays available, sellable, reserved and damaged quantities, batch expiry and permission-controlled landed unit cost.

Every stock change comes from an immutable inventory movement. A database trigger applies movement deltas to balances, and a guard rejects direct INSERT/UPDATE/DELETE on inventory. Existing balance constraints reject negative stock and reservations above sellable stock. Database owners must not bypass triggers during maintenance.

**Adjust** requires a signed base-unit delta, a bucket (sellable, damaged or reserved), and a reason. A posted adjustment, its movement and audit record commit together. Reserve with a positive reserved delta and release with a negative delta. Sales-linked reservations are deferred to the sales phase. Correct an erroneous adjustment through a new compensating adjustment, preserving history.

Receipt and adjustment POSTs accept request UUIDs for idempotent retries. Reusing a UUID with different content is rejected. Row locking and version checks prevent concurrent stale writes. An adjustment cannot remove stock that is reserved.

## Permissions and API

All routes are under `/api/v1` and enforce centralized Go permissions:

| Routes | Permission |
| --- | --- |
| GET/POST `/receiving`, GET `/receiving/:id`, `/receiving/options`, `/receiving/shipments/:id` | `receiving.manage` |
| GET `/inventory`, `/inventory/warehouses`, `/inventory/movements` | `inventory.view` |
| POST `/inventory/adjustments` | `inventory.adjust` |
| Optional cost fields in inventory/movement responses | `finance.view_landed_cost` |

List APIs support `page` and `page_size` (up to 100). Receipts and inventory support `q`; inventory supports `warehouse_id`; movements support `warehouse_id` and `batch_id`. Quantities, versions and costs are strings. Cost fields are omitted by the server without finance permission.

The inventory UI requires inventory view access; staff who post adjustments through it also need inventory adjust access. No new role was introduced.

## Verification

Verified on 2026-09-25:

- `make check`: Go race tests/vet, frontend lint, TypeScript and production build.
- `make test-integration`: real PostgreSQL migration, permission, receiving and stock tests, plus earlier module regressions.
- `make test-e2e`: all 15 browser tests passed, including shipment → costing → receipt → inventory → reservation → movement history.
- Desktop inventory and 375px receiving screenshots inspected.

Backend cases cover duplicate concurrent receipt retries, carton conversion changes, cost/count mismatch rollback, reserved/available arithmetic, controlled correction, stale versions, over-reservation, forbidden direct balance edits, immutable posted records, movement/balance reconciliation, cost permissions and wholly missing/damaged receipts. Test fixtures use disposable databases, not the user's business records.
