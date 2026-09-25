# Landed cost — Phase 9

Open a shipment and use **Landed cost**. Select an allocation method, review sellable base quantities, enter a confirmation note, and calculate a preview. The cost journey and item table show purchase, transport, expenses, landed cost and actual unit cost separately.

**Purchase cost in MMK + transportation cost + active shipment expenses = landed cost.**

**Item landed cost ÷ item sellable quantity = actual cost per base unit.**

The full cost stays with its item even when some goods are damaged or missing. Zero sellable quantity retains the entire item cost, with a null unit cost: it must later be handled as a loss, never as free sellable stock. No loss ledger entry or stock receipt is created in this phase.

## Allocation methods

Both transportation and active shipment expenses use the selected method. Each pool reconciles independently.

| Method | Per-item basis |
| --- | --- |
| Quantity | Expected shipment base quantity, including goods subsequently lost or damaged |
| Purchase value | Historical MMK purchase cost assigned to the shipment item |
| Weight | Explicit total kilograms for the item; positive for every item |
| Carton quantity | Explicit cartons, including fractions; zero is allowed for non-carton goods |
| Manual | Explicit MMK transport and expense allocation for each item |

For proportional methods: `pool × item basis ÷ total basis`. A positive cost pool requires a positive total basis. Manual amounts must sum exactly to their respective pools. Sellable quantity is independent of the allocation basis and cannot exceed expected quantity; excess receiving requires the later receiving workflow.

## Precision and historical cost

Go uses `math/big.Rat` and integer 0.0001-MMK units; PostgreSQL uses NUMERIC. Money never passes through float types. Unit cost is rounded half-up to eight decimals, consistent with the database's generated column.

Proportional allocation floors each share to four decimals, then distributes remaining 0.0001-MMK units by largest fractional remainder. Stable shipment-item ID order breaks ties. The sum of item allocations always equals the source pool, including tiny fractions.

Purchase line MMK costs use the immutable purchase amount's transaction exchange rate. Cumulative rounding in purchase-line order reconciles line costs to the posted purchase total. For split shipments, the remaining historical line cost is allocated proportionally over its remaining unfinalized quantity. The final portion absorbs the remaining fraction. Earlier finalized costs never change. Finalization order can affect a 0.0001-MMK rounding fraction; it cannot create or lose purchase cost. A preview becomes stale if another shipment finalizes against the same purchase line.

Voided expenses are excluded. Loading, unloading and additional transport fees are already included in the transportation pool; do not enter the same charge again as a separate expense.

## Finalization and permissions

Viewing and previewing require `shipments.view` and `finance.view_landed_cost`. Finalization additionally requires the sensitive `costs.finalize` permission, configurable for Staff Admin. Super Admin has full access. These policies are enforced by Go middleware.

Preview is available before arrival. Finalization requires **Arrived**, explicit sellable quantities and a confirmation note. It locks allocations, sellable-cost quantities, stages and expenses, and writes one immutable snapshot plus an audit record in one transaction. It does not mark goods received. Receiving must later reconcile its sellable counts with the confirmed costing quantities before creating finalized batches.

Shipment versions prevent stale edits. A server-generated preview token covers both source data and user inputs. A different shipment consuming the shared purchase-cost rounding budget also invalidates that token. Concurrent finalizations serialize on shipment and purchase-item locks; only one snapshot can be inserted. Repeated finalization returns 409 and cannot duplicate amounts. Reload after an uncertain network response.

No correction/reversal screen is provided for finalized costs yet. Do not overwrite a finalized snapshot to correct a mistake; a future audited adjustment workflow must preserve it.

## Integration contract for later inventory and profit phases

Finalized shipment items expose `purchase_cost_mmk`, `allocated_transport_mmk`, `allocated_expense_mmk`, `costing_sellable_quantity`, generated `landed_cost_mmk` and generated `actual_unit_cost_mmk`. Their parent must be finalized and have a `shipment_costings` snapshot before these are authoritative.

Receiving must allocate these preserved totals into received batches without duplicating them across partial receipts. Sales/COGS/profit must use finalized landed batch costs; missing or null cost must block sale costing, never fall back to supplier purchase price. Existing batch and sale-cost snapshot tables remain the downstream model. This phase does not implement sales or profit-report screens.

## API

- `GET /api/v1/shipments/:id/landed-cost`: source quantities/cost pools and optional immutable snapshot.
- `POST /api/v1/shipments/:id/landed-cost/preview`: `{version, method, notes, items}`.
- `POST /api/v1/shipments/:id/landed-cost/finalize`: the same input plus the returned `preview_token`.

Each item contains `id`, `sellable_quantity`, optional `weight_kg` / `carton_quantity`, and manual-method `manual_transport_mmk` / `manual_expense_mmk`. All quantities, amounts and versions are strings. Every shipment item must appear exactly once. Finalization returns 201; invalid input returns 400; missing grants return 403; changed/closed/finalized data returns 409.
