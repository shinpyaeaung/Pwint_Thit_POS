# Shipment and transportation — Phase 8

Open **Shipments** to search/filter the paginated list, create a shipment from posted purchase items, and follow its transportation timeline. Quantities are expressed in product base units. A shipment may combine purchases and suppliers. Super Admin can add a destination warehouse from the creation form.

Each stage is added separately, with no fixed stage limit. It records origin, destination, provider, transportation type, vehicle, departure/arrival, transport/loading/unloading/additional MMK fees and notes. Timeline and expense history load 20 records per page. Shipment details show exact transport and active-expense totals.

Expenses store currency, original amount, transaction exchange rate, MMK amount, date, category, description and notes. MMK always uses rate 1. Foreign expenses require exchange-rate permission and retain their transaction rate. Corrections use a reasoned void followed by a replacement; voided records remain visible and are excluded from expense totals.

## Permissions

| Operation | Backend permission |
| --- | --- |
| List/details/items/stages/expenses | `shipments.view` |
| View monetary fields | `shipments.view_cost` |
| Create shipment / update status / reference choices | `shipments.manage` |
| Add stages / expenses | `transportation.manage` + `shipments.view_cost` |
| Edit stages / void expenses | Above + `costs.change_transport` |
| Record foreign expense rate | Above + `exchange_rates.manage` |
| Create warehouse | `settings.manage` |

Grant view and management permissions together for staff who use the screens. Super Admin receives all permissions. Migration 12 copies existing explicit `finance.view_landed_cost` grants into the new shipment-cost permission once; subsequent grants are independent. Unauthorized monetary fields are omitted from API responses, not merely hidden in the UI.

## Integrity and workflow

- Creation locks posted purchase items in a stable order and checks remaining base quantity inside the transaction. Concurrent requests cannot over-allocate a purchase.
- Shipment creation, stages and expenses accept unique `request_id` UUIDs. A duplicate returns 409 without a second write. After an uncertain network result, reload the list/details before retrying.
- Child writes/status updates require the current string `version`. Parent locks and version checks reject stale changes with 409; the UI preserves the failed form for review.
- All writes include an audit record in the same transaction. Cost changes require a sensitive permission. Records with payment allocations cannot be edited/voided here.
- Payment status is derived from posted outgoing payment allocations: unpaid, partially paid or paid. This phase displays status; payment-entry screens belong to the payment module.
- Status moves from Preparing → In Transit → Arrived. Departure and arrival dates are validated. Preparing/In Transit may be cancelled when no active receiving exists; cancellation releases purchased quantities while preserving cost history.
- Received is reserved for the goods-receiving workflow. Cancelled, received and cost-finalized shipments reject further mutations. Arrived shipments still allow transport/expense completion before finalization.
- This phase does not receive inventory or allocate landed cost. Future costing must exclude voided shipment expenses and preserve historical snapshots.

## API

All paths below have the `/api/v1` prefix. Amounts, rates, quantities and versions are decimal strings.

- `GET /shipments?q=&status=&page=1&page_size=20`, `POST /shipments`
- `GET /shipments/:id`, `/items`, `/stages`, `/expenses` (stages/expenses paginate)
- `PUT /shipments/:id/status`
- `POST /shipments/:id/stages`, `PUT /shipments/:id/stages/:stageID`
- `POST /shipments/:id/expenses`, `POST /shipments/:id/expenses/:expenseID/void`
- `GET /shipment-options?kind=warehouses` or `kind=purchases&q=...` (up to 50 matching purchased items)
- `POST /warehouses`

See `frontend/src/pages/shipments` for request field names and `backend/internal/shipments` for validation. Apply migration `000012_shipments.sql`, then regenerate queries with `make generate` when SQL changes.
