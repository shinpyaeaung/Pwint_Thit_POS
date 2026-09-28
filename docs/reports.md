# Phase 20 — Reports

Open **Reports** in the sidebar (`/reports`). The report catalog only lists reports the current user can access. Every report supports Today, This Week, This Month, This Year and Custom Date Range, refresh, exact totals and server pagination (10, 25, 50 or 100 rows in the UI; 1–100 via the API). Wide tables scroll within the page on mobile.

## Date semantics

Dates are inclusive Myanmar business dates (`Asia/Yangon`), resolved by the backend. This Week starts Monday; week/month/year presets end today. A custom range requires both dates, with `from <= to <= today`. Invalid dates, duplicate or unknown filters, invalid pagination and unknown report IDs return clear errors.

Event reports use `[from 00:00, day-after-to 00:00)` in Myanmar time, including events immediately before midnight and excluding the following day. Dates in the table are displayed in the same timezone.

- Inventory reconstructs opening balances before `from`, period changes, and closing balances through `to` from immutable movements. It includes existing opening stock even when there is no activity in the period. Available quantity means sellable minus reserved, not POS eligibility; expired stock remains physical stock. Different products' units are never added into a misleading quantity total.
- Customer Debt and Supplier Payables are outstanding balances at the selected end date, including unpaid older invoices. `OPENING` labels invoices before `from`; `PERIOD` labels invoices within the range. Payments, credits and refunds after `to` do not affect the result. Only positive invoice balances are included; credits on another invoice do not silently cancel debt.
- Shipment Report selects shipments created in the period and shows their current lifecycle state, including cancelled shipments. This is not a reconstruction of the shipment's former status.
- Transportation Cost selects stages by departure date, falling back to creation date. Cancelled shipments are excluded. Unfinalized costs are explicitly provisional; finalized costs remain protected by the existing costing rules.

Historical reports reconstruct business event dates from the currently recorded immutable ledgers. They are not archived copies of what an operator saw on a past day; later-entered backdated documents can affect a past period.

## Reports and access

All endpoints require `reports.view` **and** every additional permission in the table. The API enforces these rules independently of the UI. A reports-only account receives an empty catalog and cannot read any report data.

| Report / API suffix | Basis | Additional permissions |
| --- | --- | --- |
| Sales / `sales` | Posted sales and negative return credits on their own dates; includes retail and wholesale modes | `sales.view` |
| Purchase / `purchases` | Posted purchases and supplier returns; original currency and saved exchange rate alongside MMK | `purchases.view`, `purchases.view_cost` |
| Profit & Loss / `profit-loss` | Existing authoritative `app.profit_summary`: net sales, landed COGS, gross profit, net operating expenses, net profit | `finance.view_profit` |
| Product Profitability / `product-profitability` | Product-level net quantity, revenue, recorded batch COGS and gross profit after returns | `finance.view_profit` |
| Transportation Cost / `transportation` | Transport, loading, unloading and other fees by stage/provider/route | `shipments.view`, `shipments.view_cost` |
| Shipment / `shipments` | Lifecycle, warehouse, dispatch/arrival dates, line/stage counts and finalization status | `shipments.view` |
| Inventory / `inventory` | Opening/closing sellable, reserved, damaged and available quantities by product/batch/warehouse | `inventory.view` |
| Stock Movement / `stock-movements` | Immutable signed bucket movements, reasons and recorded-by user | `inventory.view` |
| Damage / `damage` | Receiving damage, damaged/discarded sales returns, and stock damage/disposal/reduced-sale records | `damage.manage`, `finance.view_landed_cost` |
| Missing Product / `missing` | Receiving shortages and later missing-stock incidents | `damage.manage`, `finance.view_landed_cost` |
| Customer Debt / `customer-debt` | Invoice ledger balances through the end date | `customers.manage` |
| Supplier Payables / `supplier-payables` | Invoice ledger balances in MMK at historical transaction values | `purchases.view`, `purchases.view_cost` |
| Expense / `expenses` | Operating expense events with immutable negative reversal offsets on their reversal date | `expenses.manage` |
| Currency Purchase / `currency-purchases` | Purchased, returned and net original amounts grouped by currency, plus recorded MMK totals | `purchases.view`, `purchases.view_cost` |

## Financial boundaries

Money and quantity arithmetic runs in PostgreSQL `numeric`. JSON represents numeric row values as exact decimal strings; the frontend only formats them. Count metadata remains integer-valued. Totals cover the complete filtered result, not just the visible page. Each report's rows, count and summary come from one statement snapshot.

Profit never uses supplier price as a substitute for landed cost. Missing sale allocations withhold affected product profit and aggregate profit. Product return COGS uses the same cumulative rounding as the existing P&L so repeated partial returns reconcile to recorded batch costs. Payment collection does not create revenue. Original-currency totals are grouped by currency; only MMK totals can be combined.

Damage and missing reports describe activity, not current damaged inventory or extra operating expenses. Repeated lifecycle events can refer to the same units; their estimated losses must not be added again to the P&L. Receiving discrepancy estimates use finalized batch landed cost, never supplier-price fallback. If a receiving discrepancy lacks complete cost, the aggregate estimate is withheld. Current damaged quantities are available in the Inventory Report.

## Architecture

`backend/internal/reports` separates handlers, service orchestration, sqlc repository dispatch, models/catalog, authorization middleware/policies, and input validation. Each report has a separate SQL query file. Migration 22 adds read-only helpers/views and date indexes; it does not alter recorded financial values or stock. Existing auth middleware, report permission, pgx connection pool, P&L function, ledgers, shared table, fields, loading/empty states and exact-decimal formatting are reused.

API: `GET /api/v1/reports` and `GET /api/v1/reports/{report}?period=month&page=1&page_size=25`. Custom example: `?period=custom&from=2026-01-01&to=2026-01-31`. The response includes the authorized definition, resolved date range, summary, total count and rows. Read-only report requests perform no stock, financial or audit mutations.

Frontend report caches are scoped to user and permissions. Refresh failures hide potentially stale results and provide a retry action. No new roles, theme options or dependencies were added.

## Verification — 2026-09-27

- `make generate`: regenerated and committed sqlc query bindings from SQL.
- `gofmt`: formatted the new Go package and integration wiring.
- `make check`: passed Go race tests, vet, frontend lint, TypeScript and the production build.
- `make test-integration`: passed all database-backed suites, including all 14 reports with populated and empty ranges, exact totals, historical exchange rates, mixed currencies, customer collections, supplier and customer returns, reversal dates, Myanmar midnight boundaries, movement-derived opening/closing stock, receiving discrepancies, incomplete-cost withholding and pagination totals. Every required report permission is tested independently, including revocation.
- `make test-e2e`: all **20 tests passed**. The reports workflow runs in Chrome and WebKit, visits all 14 report views, verifies all date presets and custom ranges, exact-decimal display, empty states, failure/recovery and restricted staff access. Desktop and 375px mobile screenshots were visually reviewed.

Tests use disposable PostgreSQL databases. The report browser tests have a dedicated seeded owner account so the expanded suite respects the existing production login rate limit.
