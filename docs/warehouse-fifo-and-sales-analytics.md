# Original batches, FIFO costs, stock filters and sales analytics

## Transfers and existing data

New warehouse transfers preserve the product ID, batch ID, batch number, manufacture/expiry dates and original receipt information. Dispatch removes source stock; receipt adds to the same batch at the destination. Repeated arrivals merge into the existing `(warehouse, batch)` stock position. Transfers no longer insert batches.

Migrations 000048–000052 separate immutable FIFO cost identities from physical batch identities. Each inbound cost record retains its own arrival timestamp and price, with movement-controlled remaining sellable/damaged quantities. POS allocates the oldest available cost records within each FIFO batch, including mixed selling units in one cart; invoice allocations snapshot each cost separately. Legacy cost records preserve their historical arrival order. Multi-item transfer receipts lock destination positions in original-batch order. Reservations reduce available quantities without changing physical stock. Returns retain original sold costs, cancellation restores the dispatched cost records, and damage/missing/supplier returns use warehouse FIFO costs. Positive stock adjustments use the remaining warehouse average, or the last recorded warehouse cost when depleted. Displayed inventory unit/carton costs are averages for reference; sales and inventory valuation use the underlying exact cost records.

Transfer cargo and additional costs remain finalized in the transfer document and are allocated into its destination cost records. Fully damaged arrivals have no invented sellable unit cost. Existing historical rates and batch costs remain unchanged. A statement-level transaction rolls back stock, cost records and audit together on failure, and quantity reconciliation guards reject any divergence between physical stock and cost records.

Existing transfer-derived batches remain as historical documents. Current quantities and reservations are reclassified to the original batch through paired audited adjustments, preserving each warehouse cost. Future returns/reversals against older batches rejoin the original physical batch. Depleted legacy transfer rows are hidden from current inventory; original movements, invoices and costing history remain available.

## Stock status filters

Inventory → Stock status offers All stock, Low Stock and Out of Stock. Status views show active products once in the selected scope, including products never stocked. A selected warehouse uses only its available stock; All warehouses sums across warehouses. Expired, reserved, damaged and otherwise non-sellable stock is excluded. Low means available quantity is greater than zero and at or below the product's configured minimum. Out means zero; it does not require a minimum setting. Status selection resets pagination and uses product-level results independent of the batch/brand display grouping. Inventory-view permission is enforced by the API.

## Best-selling Products

Reports → Best-selling Products ranks products by sold base-unit quantity, then net revenue and product ID for stable ties. It shows sold, returned and net quantities, original sales, returns and net revenue. Units remain explicit; unlike product units are not summed into a misleading total quantity. Posted sales count as revenue, including credit sales; collections are not additional sales. Returns reduce revenue on their own date.

Charts show the top ten products' net revenue, daily net revenue and hourly net revenue across the complete selected date range, independent of table pagination. Date/time grouping uses Asia/Yangon and inclusive date filters with exclusive next-day timestamp bounds. All 24 hours are shown; daily charts include activity dates and disclose omitted inactive dates. Exact decimal values remain available alongside approximate chart geometry. Today/week/month/year/custom filters are supported. Access requires reports.view plus sales.view; profit/cost permissions are not required and cost data is not exposed.

## Verification

`make check` covers Go race tests/vet, frontend lint, 13 unit tests, TypeScript and production build. PostgreSQL integration covers legacy migration with reservations, no new transfer batches, multiple FIFO prices behind one stock row, mixed-unit sales, original-cost refunds, missing-stock valuation, immutable costs, rollback, concurrency, never-stocked products and Myanmar midnight report boundaries. Browser regressions cover original batch identity, both stock status filters, report access, charts, mobile layout and date controls.

Before deployment, a private dump of the existing database was restored to an isolated rehearsal database. The migration preserved 1,705 sellable units, 506 reserved units, zero damaged units and exactly 105,318,766.6667 MMK sellable value. All five existing integrity checks and four new cost-layer checks reported zero discrepancies. The rehearsal database was removed; the private backup is retained outside Git at `/tmp/pwint-before-fifo-20261103.dump`.

The completed release passed all 40 production-bundle Chromium/WebKit tests, including responsive chart inspection. It is deployed at http://localhost:8088 with healthy services, valid nginx configuration and anonymous API rejection. Final live checks again returned zero discrepancies across all nine integrity checks, with the same stock totals, reservations and valuation and no missing FIFO arrival dates.
