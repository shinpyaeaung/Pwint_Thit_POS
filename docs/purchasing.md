# Purchasing and multi-currency — Phase 7

Use **Purchases → Create Purchase** to select an active supplier, purchase date, currency, historical quote (or authorized custom rate), and product packaging. Prices are **per selected packaging unit**: two cartons at 5,000 INR each produce 10,000 INR; the base-unit quantity follows the product's packaging conversion. Review the original and MMK totals, then confirm posting. Purchase List and Purchase Details show both currencies when the user can view purchase costs. Supplier Details includes balances grouped by original currency and combined in MMK.

## Historical amounts and exact arithmetic

MMK is the base currency, fixed at 1. INR, THB, CNY and USD are seeded; authorized users can add other currencies. A transaction stores its own currency and `mmk_per_unit`, independently of later quotes. Saved quotes are append-only and cannot be updated/deleted. A selected quote must match the currency and rate and must be effective by the transaction date. There is no automated market-rate service and no automatic revaluation.

Posting atomically records the header, items, immutable `purchase_amounts` snapshot and audit record. The snapshot stores original amount, currency, rate and a PostgreSQL STORED generated MMK amount. Product name, SKU, packaging name and conversion are also captured, so later catalog changes do not rewrite new purchase lines. Migration 000011 backfills amount snapshots for existing posted purchases without modifying their original transaction rows. Legacy item labels fall back to the catalog when no label snapshot exists.

- Quantity, packaging conversion and unit price: NUMERIC(20,6).
- Discounts, taxes, line totals, purchase totals and MMK: NUMERIC(20,4).
- Exchange rates: NUMERIC(24,10), strictly positive; MMK must equal 1.
- Line amount = round(quantity × selected-unit price − line discount + line tax, 4).
- Original purchase total = sum of rounded line amounts.
- MMK total = round(original total × transaction rate, 4).

All financial API values are decimal strings. The browser preview uses BigInt fixed-point arithmetic with the same rounding sequence; Go validates decimal strings and PostgreSQL calculates the authoritative totals. No financial calculation uses Number/parseFloat or floating-point types. Excess precision, negative amounts, non-positive quantities/rates, NaN, discounts above gross line value and storage overflow are rejected.

**Historical example:** January: 10,000 INR × 25 = 250,000 MMK. March: adding a quote of 27 leaves January at 250,000 MMK. March purchases using 27 have their own 270,000 MMK total.

The date-only UI uses the Myanmar business-day cutoff (23:59:59 +06:30) for purchases and quote eligibility; a new date-only quote is effective at 00:00:00 +06:30. The API accepts explicit RFC3339 timestamps. Due dates cannot precede the supplied purchase date.

## Posting, retries and balances

This phase creates **posted purchases**. A draft row exists only inside the creation transaction while its items are written. Failures roll the transaction back entirely. There is no purchase edit, delete, cost-change or reversal endpoint in this phase. Existing draft/cancelled/reversed records remain readable. Corrections to posted purchases need the later authorized reversal workflow, not a changed historical rate.

Every create request includes a UUID `request_id`. A transaction-level advisory lock plus a unique request key makes concurrent/retried identical requests return the same purchase (201 first, 200 replay); changed data with the same key returns 409. Purchase number and supplier invoice uniqueness also prevent accidental duplication. Active suppliers/currencies and product packaging are locked during validation; a stale packaging conversion returns 409 for review instead of silently changing the order.

Supplier balances use the existing `supplier_payables` view: posted purchases minus posted payments and return credits, plus posted refunds. Foreign amounts are grouped by currency, never added across currencies. MMK balances use each purchase's original rate. Draft purchases and draft payments are excluded. Overdue/partial/unpaid status comes from the existing ledger rules. Posting a purchase neither receives inventory nor records a payment.

## API and permissions

All paths below are under `/api/v1` and require authentication. Super Admin has full access; Staff Admin needs explicit grants enforced by Go.

| Route | Required access |
| --- | --- |
| GET `/currencies` | Any of purchases.view, purchases.create, exchange_rates.manage, settings.manage |
| POST `/currencies` | settings.manage |
| GET `/exchange-rates?currency=INR&as_of=<RFC3339>` | Any of purchases.create, purchases.view_cost, exchange_rates.manage |
| POST `/exchange-rates` | exchange_rates.manage |
| GET `/purchase-options?kind=suppliers/products&q=...` | purchases.create + purchases.view_cost |
| GET `/purchases` and `/purchases/:id` | purchases.view |
| POST `/purchases` | purchases.create + purchases.view_cost; custom foreign rates also require exchange_rates.manage |
| GET `/suppliers/:id/balance` | suppliers.view + purchases.view_cost |

Cost permission is evaluated by the centralized authorization service. Purchase reads without purchases.view_cost omit the rate, original/MMK totals, payable figures and line prices/discounts/taxes entirely. The client cannot request those fields by passing a flag. Creation screens need purchases.view as well to open the saved details. Reference choices expose only the names/codes and packaging needed to create a purchase, not prices or supplier contact notes.

Purchase list supports `q` (purchase/invoice/supplier), `currency`, `status`, `page`, `page_size` (1–100, default 20). Counts and rows use one SQL snapshot. Supplier/product pickers return up to 50 matches and support search. Historical quote selection returns the latest 100 quotes at or before the selected date; selecting an earlier purchase date exposes older history. Currency setup creates codes; it does not mutate currencies or historical quotes.

Payments, receiving, landed costs, returns and reversal entry screens remain separate future vertical slices. This phase reads existing ledger records for balances rather than introducing alternate balance fields.
