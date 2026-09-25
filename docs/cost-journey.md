# Cost Journey UI — Phase 10

`frontend/src/components/costs/cost-journey.tsx` provides the shared Pwint Thit journey. A numbered route connects original purchase, historical exchange rate, assigned MMK purchase cost, transport, other costs, landed cost, selling price and gross profit. Red emphasizes landed cost; yellow marks the source-to-shelf route. The grid adapts from four columns to two and then a compact vertical sequence. Motion respects reduced-motion settings.

## Where it appears

- Purchase Details: the original purchase total and saved exchange rate, plus separate finalized shipment-item journeys.
- Product Details: paginated historical shipment-item allocations selected individually; no blending of historical costs into a current product price.
- Shipment Details: historical source lines and known fees before allocation, then the calculated/finalized journey.
- Costing preview and finalized result: the complete cost breakdown with the existing per-item allocation table.
- UI library: the explicitly illustrative 10,000 INR × 25 MMK → 250,000 + 40,000 + 10,000 = 300,000 MMK example, with a 340,000 MMK selling scenario and 40,000 MMK estimated gross profit.

Purchase-source disclosure shows original full-line amounts and the shipped/purchased base quantities. Partial shipments label converted purchase as the assigned MMK cost. Mixed sources retain each currency and historical rate; the UI never invents a blended exchange rate. Historical rounding remains as calculated by Phase 9.

## Selling price and profit

Selling records/pricing are not implemented yet. Until then, the last two steps show unavailable values and an optional, clearly labelled selling-price scenario for users with `finance.view_profit`. The scenario uses the total selling value for the same allocation/quantity as the displayed landed cost, and exact BigInt subtraction. Negative results are labelled Loss; zero is preserved. Invalid input does not produce a numeric profit. Inputs are local component state only and are not saved as sales or prices. No supplier-price fallback is used. Zero-sellable allocations disable the scenario.

## Access and API

Backend authorization protects all financial sources. Product/purchase journey history requires the corresponding view permission plus `finance.view_landed_cost`. Shipment costing retains its existing shipment-view and landed-cost permissions. UI guards avoid requesting history for unauthorized accounts. No additional roles, financial writes or schema migrations were needed.

Read-only routes:

- `GET /api/v1/products/:id/cost-journeys?page=1&page_size=10`
- `GET /api/v1/purchases/:id/cost-journeys?page=1&page_size=10`
- Existing `GET /api/v1/shipments/:id/landed-cost` now also returns `purchase_sources`.

History includes only finalized shipment allocations backed by a cost snapshot. Dates/IDs provide deterministic pagination. Current stock, batch valuation, actual selling prices and realized profit remain separate future features.
