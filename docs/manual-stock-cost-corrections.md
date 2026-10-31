# Correct landed cost for stock entered manually

As Super Admin, open **Inventory**, find the batch created through **Add existing stock** or a warehouse-transfer batch originating from it, and choose **Correct landed cost**. The action is also available inside expanded grouped inventory. Enter the correct landed cost per individual base unit (Piece, Bottle, etc.), including transport, and a correction reason. The dialog shows current cost, remaining quantities, the carton-cost equivalent and correction history.

The correction applies to the selected batch's remaining sellable and damaged stock at that warehouse. Reserved stock must be released first. A fully depleted batch has no remaining stock to correct. Purchase-origin batches remain outside this action. Migration 000047 follows transfer ancestry, including multiple transfers, so manually originated stock can be corrected at its current warehouse. Enter the complete corrected landed unit cost including transfer/cargo costs; the correction does not automatically add those fees again. Other warehouses and original transfer snapshots remain unchanged.

## Preserved history

Migration 000046 adds immutable correction records. A correction creates a new finalized manual-stock batch, retaining the original received date, manufacture/expiry dates and carton size. Paired dated adjustments remove remaining quantities from the old batch and add identical sellable/damaged quantities to the replacement. The old batch, original manual entry, past stock movements, invoices, refunds and transfer costs are never overwritten. Warehouse selling prices and cash/payment records do not change.

Future FIFO sales of the replacement use the corrected actual cost. Completed sales and past profit keep their recorded cost. Returns against an older sale retain that sale's original batch/cost lineage; stock subsequently returned to an old batch can be reviewed and corrected separately. Corrections do not retroactively restate historical profit.

Cost entry accepts non-negative MMK values with up to four decimal places. Replacement batch total cost is the remaining physical quantity multiplied by the entered cost and rounded to four decimal places, following existing manual-stock rules; actual unit cost derives from that stored total. Every quantity and money operation uses PostgreSQL exact numeric arithmetic.

## Controls

Both the API and SQL function require active Super Admin status, regardless of configurable staff grants. Product and inventory locks serialize corrections with FIFO checkout; the inventory version prevents stale edits. Identical request retries return the same replacement batch. A reused request with changed contents is rejected. Batch creation, both stock buckets, the correction record and audit commit atomically. Unknown network/server outcomes lock the dialog to retrying the same correction.

Correction history records actor, time, reason, old/new batches, quantities and old/new actual costs. Stock movements expose the adjustment reference and reason. Historical movement-derived stock and values remain intact because correction movements occur at the correction time.

## Verification — October 31, 2026

- Full PostgreSQL integration suite passed. New regressions cover all-grants staff denial, reserved-stock rejection, stale versions, exact sellable/damaged preservation, unchanged original cost and selling prices, retained receiving date/carton size, immutable correction history, duplicate requests, concurrent edits and audit-failure rollback.
- `make check` passed: Go race tests/vet, lint, 13 frontend unit tests, TypeScript and production build.
- All 40 production-bundle Chromium/WebKit cases passed. The manual-stock browser workflow completes a sale and refund, transfers 23 remaining pieces twice (including cargo that changes cost from 100 to 101 MMK), corrects them to 120 MMK, checks original invoice cost/profit unchanged, confirms a future FIFO quote uses 120 MMK, and opens correction history on a mobile screen.
- Tests operate on disposable databases. No real stock cost was changed during implementation or verification.
- Migrations 000046–000047 and updated API/frontend deployed at http://localhost:8088. All services healthy; nginx syntax valid, unauthenticated correction API returns 401, and all five existing-data integrity checks reported zero before and after deployment.

The transfer follow-up also verifies multi-leg ancestry, unchanged stock at other warehouses and protected purchase-origin batches. Reduced-price damaged sales now offer Cash or Bank transfer with a matching receiving account and optional bank reference. A receiving account is required for actual payments so the money ledger stays complete; recording damage alone uses Record issue without a payment account. Chromium verifies cash sales and WebKit verifies bank sales and the exact bank ledger entry.
