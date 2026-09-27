# Dashboard (Phase 19)

The dashboard opens at `/` for users granted `dashboard.view`, and at `/dashboard`. The original connectivity page is available at `/workspace`. Users without dashboard access retain the connectivity page as their home.

`GET /api/v1/dashboard` returns a consistent PostgreSQL statement snapshot. All dates use Asia/Yangon; month means month-to-date. Numeric money and quantity values remain decimal strings through the API and UI. The page refreshes every minute and on focus, supports manual refresh, and explicitly marks cached results as potentially stale when a refresh fails.

## Financial definitions

- Today's Sales and Monthly Sales are posted sales revenue less posted return credits, including unpaid credit sales. Collecting a debt does not create revenue again.
- Today's Profit is today's **net** profit. The monthly panel shows gross profit, operating expenses and net profit separately. Both reuse Phase 18's authoritative `profit_summary`, using historical sale batch cost allocations, with profit withheld if any sale lacks complete costs.
- Inventory Value is current **sellable** quantity multiplied by finalized actual landed unit cost. It includes reserved units and expired stock still physically held; damaged stock is excluded. If any positive sellable stock position has incomplete cost, the whole value is withheld. This is a book-value indicator, not a market valuation or full general ledger.
- Customer/Supplier Debt sums positive outstanding invoice balances from their payment/credit/refund ledgers. A credit on one invoice does not silently cancel a different invoice's debt. Supplier amounts use the stored transaction exchange rate, never today's rate.
- As documented in [expenses and profit](expenses-profit.md), damage/missing estimates and supplier-return adjustments are separate from recorded operating expenses. They are not automatically counted again as expense entries.

## Stock and activity

Low Stock includes active products with a configured minimum, whose POS-eligible unreserved quantity across all warehouses is at or below that minimum. Expired, uncosted and invalid expiry-tracked stock cannot satisfy the threshold. Zero-stock products remain visible.

Expiring Products counts batches with positive sellable stock that are already expired or expire within 60 days. Expired batches are identified separately; earliest expiry comes first. Damaged Products counts distinct products currently holding damaged quantity, rather than historical damage reports. Each list previews six entries and links to its operational module; quantities retain the product's base unit.

Recent Transactions shows the latest eight visible posted sales, purchases, expenses, expense offsets and sales returns, ordered by business event timestamp. It is an activity preview, not a cash-flow report. Expenses retain their original entry alongside any reversal.

## Permissions

The backend requires `dashboard.view` and omits each unauthorized section:

| Section | Additional permission |
| --- | --- |
| Sales and recent invoices | `sales.view` |
| Daily/monthly profit statement | `finance.view_profit` |
| Low stock, expiry | `inventory.view` |
| Inventory value | `inventory.view` + `finance.view_landed_cost` |
| Damage | `damage.manage` |
| Customer debt | `customers.manage` |
| Supplier debt | `purchases.view_cost` |
| Recent purchases with totals | `purchases.view` + `purchases.view_cost` |
| Recent expenses and offsets | `expenses.manage` |
| Recent sales returns | `returns.manage` |

Dashboard access alone reveals no financial or stock data. There are no new roles and no stock/financial writes in this feature.

## Verification

Integration tests assert actual landed profit, historical supplier balances, inventory cost completeness, low-stock/expiry/damage counts, and server-side field omission for restricted staff. The real-stack Chrome and WebKit workflows compare dashboard profit with the finance report, check desktop/mobile layouts, simulate refresh failure/recovery, and verify a dashboard-only staff account cannot see financial data.

Verified on 2026-09-27:

- `make generate` regenerated the pinned sqlc bindings.
- `make check` passed Go race tests, vet, frontend lint, TypeScript and the production build.
- `make test-integration` passed against disposable PostgreSQL databases, including the regression that retains both the original expense and its reversal in recent activity.
- `make test-e2e` passed all 18 real-stack browser tests, including the dashboard workflow in Chrome and WebKit. Desktop and 375px mobile screenshots were visually reviewed.

Dashboard cache entries are scoped to the current user and permission set. The dashboard is read-only and preserves the existing accounting definitions.
