# Phase 13 — Point of sale

Open **Point of sale**. Choose the warehouse and retail/wholesale pricing. Users with `products.update` can use **Prices** beside a product to set retail and wholesale prices for each selling unit, including cartons. Both are exact MMK amounts per selected pack. Price changes are audited; completed invoice prices and historical batch costs remain unchanged.

## Daily checkout

- Scan a product or packaging barcode and press Enter, or search by name/SKU and choose Add.
- F2 focuses product search, F4 focuses customer search, and F8 reviews checkout. Cart changes and decimal totals update locally without a network round trip. Search uses short debouncing and cached results; scan lookup checks an exact barcode before adding.
- Choose the selling unit and quantity on each cart line. One line per product uses one selected unit. Repeated scans of the same unit increment quantity. A different packaging barcode for a product already in the cart asks the cashier to change that line's unit rather than silently mixing conversions.
- Choose an existing customer or, with `customers.manage`, add a name/phone/type and credit limit. Walk-in customers must pay in full.
- Authorized discounts are fixed MMK amounts per line, not percentages. `sales.discount` and an explanation are required. Selling below actual FIFO batch cost requires `sales.sell_below_cost` and a reason; it remains visibly flagged in review.
- Choose cash, bank transfer, mobile payment or other. Leave tender blank for exact payment. Cash overpayment produces change; only the invoice amount is posted as payment. Non-cash overpayment is rejected.
- Partial/unpaid checkout requires a named customer, a due date on/after today's Myanmar business date, and sufficient unused credit limit. A zero credit limit means full payment. Existing posted debt is checked while the customer row is locked.
- Review and complete the sale, then print the invoice. Checkout has no decorative animation. Internal costs and profit are excluded from printed invoices.

Carts are temporary in-memory Zustand state, not posted records or offline orders. A page reload clears the cart. Stock availability shown during search is advisory; the backend revalidates it before quoting and again before posting. POS consumes unreserved stock only; reserved stock must be released through its authorized workflow first.

## Exact FIFO and atomic posting

The database selects available finalized batches with known actual unit cost, ordered by received date and batch ID. Expired stock, damaged/reserved quantities, uncosted batches, and undated batches for expiry-tracked products are excluded. Expiry uses Asia/Yangon and goods remain valid through their expiry date.

The transaction locks affected products and inventory in stable order, rechecks current prices and packaging, and copies FIFO allocation quantities and actual batch costs to `sale_item_batches`. It posts the invoice/items, inventory movements, payment/allocation and audit record atomically. Inventory balances change only through the movement trigger. A failure rolls everything back.

Quotes do not mutate stock or financial records. A quote hash detects changed allocations, amounts or customer/warehouse details before posting; it is a freshness check, not an authorization token. Checkout repeats all permission and integrity checks. Each checkout has a request UUID. Identical retries return the existing invoice; different contents with the same UUID are rejected. Concurrent terminals cannot sell the same last units. An uncertain network outcome keeps the reviewed request available for a safe retry.

Financial inputs remain decimal strings. Local preview uses scaled integers; PostgreSQL NUMERIC performs authoritative calculations. Each sale line and each allocated batch's COGS round to four MMK decimal places, using stored eight-decimal landed unit costs. Profit is revenue minus allocated landed cost, never supplier purchase price.

Invoice snapshots preserve product/customer labels, packaging, sale prices, discounts, tender/change and original payment/debt values. **Invoices** and printed documents explicitly show debt at checkout; subsequent debt collection and payment management are separate workflows. This phase supports one payment method per checkout. Returns, offline sales, split tender, promotions, customer-specific price lists and a full customer management screen are not part of this POS slice.

## Server permissions

| Action | Permission |
| --- | --- |
| POS, product search, customer selection, quote | `sales.create` |
| Complete checkout | `sales.create` and `payments.manage` |
| Set selling prices | `products.update` |
| Add customer / assign credit limit | `customers.manage` |
| Discount | `sales.discount` |
| Sell below actual cost | `sales.sell_below_cost` |
| Invoice list / other staff invoices | `sales.view` |
| View own checkout invoice | `sales.create` |
| Internal FIFO costs | `finance.view_landed_cost` |
| Gross profit | `finance.view_profit` |

All protected API operations use the centralized Go permission vocabulary. No new role was added. Cost/profit fields are removed from API responses without the corresponding permissions.

## API and verification

Routes: `/api/v1/pos/products`, `/pos/warehouses`, `/pos/customers` (GET/POST), `/pos/prices` (PUT), `/pos/quote` (POST), `/pos/checkout` (POST), `/sales`, `/sales/:id`.

Backend integration tests cover cross-batch FIFO, reserved/expired exclusions, immutable history, quote purity, stale prices, concurrent retries, two terminals competing for stock, below-cost/discount permissions, hidden finance fields, cash change, credit limits, payment allocation and customer debt. Browser tests exercise receiving → finalized batch history → price setup → carton barcode → wholesale discount → customer → payment → invoice/print → inventory movement in Chrome and WebKit. All fixtures are confined to disposable databases.

Verified: `make check`, `make test-integration`, and all 18 browser tests (`make test-e2e`) passed. Desktop/mobile POS and printed invoice screenshots were visually inspected.

## Phase 14 — Sale transaction safety

The Go checkout service explicitly begins one PostgreSQL transaction, executes the complete posting function through that transaction, and commits before returning success. Error/cancellation cleanup rolls back using a bounded independent context. Quotes remain read-only previews. All invoice, item, FIFO cost snapshot, movement-triggered balance, payment/allocation, posting and audit writes share the same transaction.

Integration tests inject database failures at 11 points: sale creation, item creation, batch cost recording, movement insertion, inventory update, payment creation, allocation, payment posting, sale posting, audit insertion and deferred COMMIT. Every failure must preserve the complete before-state of all affected ledger tables and inventory. The same request then succeeds, and concurrent retries produce only one sale. Invoice sequence gaps after rollback are expected and do not represent posted sales.
