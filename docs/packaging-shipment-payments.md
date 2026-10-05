# Packaging, shipment and supplier payment implementation

Reviewed the October 5 requirements against the v1.2 baseline before changing code.

## Existing foundations retained

- `products` + `product_units`: per-product conversion, one base stock unit, separate selling prices per packaging. Purchase and sale lines snapshot conversions; used base units cannot change.
- `purchases` + `purchase_items`: exact decimal original-currency amounts, immutable posted documents/rates and calculated base quantities. Saved purchases can await transportation and payment independently.
- `shipments` + `shipment_items`: partial and consolidated allocation with locked over-allocation checks. Multiple transportation stages/providers and expenses already feed finalized landed cost.
- Receiving creates immutable movements and finalized batch costs. Inventory already displays full cartons plus loose units. POS uses FIFO actual costs, not supplier prices.
- `payments` + `payment_allocations`: immutable posting and ledger-derived balances already existed, but supplier-payment entry and history were missing.

## Changes

- Product form has an explicit purchase-packaging selector and independent retail/wholesale prices for every selling unit, plus optional MMK reference purchase prices and a per-base-unit reference cost preview. Reference prices default new MMK purchase lines; they never replace historical purchase or actual batch costs. Existing historical transactions remain unchanged.
- Purchase entry previews base stock quantity and purchase cost per base unit. Actual cost still comes from finalized landed costs.
- Purchase workspace shows purchased, assigned and remaining package quantities beside base-unit remainder. Shipment entry also accepts purchase-package counts and converts them to base units before server validation.
- POS accepts separate carton and bottle lines for one product. Quotes reserve FIFO quantities across earlier lines, preventing double-use of a batch and checking total availability before posting.
- Supplier Payments page provides search, pagination, unpaid/partial/paid filters, payment entry, history, and configurable named payment methods. Purchase details expose the same payment section directly.
- Supplier payments use explicit transactions, request deduplication, purchase row locks, exact decimals, overpayment rejection and immutable audit/history. Payment entry requires purchases.view, purchases.view_cost and payments.manage; method creation requires settings.manage.
- Method names are snapshotted; categories retain compatibility with existing sales/accounting. Six initial methods include Cash, KBZPay, KBZ Banking, Yoma Banking, Bank Transfer and Other.

## Confirmed business decision and boundaries

The user confirmed supplier and transport-provider debts remain separate. Transport contributes to landed cost but does not inflate supplier invoice debt. Payment entry settles in the purchase currency at its stored historical rate. Cross-currency settlement/FX gains, supplier advances and credit balances are outside this implementation. Purchasing operational progress, shipment status and payment status remain independent; the purchase workspace's completion indicator describes goods receipt/inventory completion.

Existing records with an incorrectly chosen base unit are not silently converted; their movement and financial history must remain intact. Configure correct packaging for new products, or use the existing controlled corrections for historical mistakes.
