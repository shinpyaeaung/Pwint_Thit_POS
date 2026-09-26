# Phase 17 — Damage, missing stock and returns

## Stock exceptions

**Damage & missing stock** searches product/batch/warehouse stock and records quarantine damage, missing available or damaged stock, and disposal of damaged stock. Damage moves quantity from available to damaged; missing/discard removes it from its selected bucket. Reserved quantity cannot be consumed. All operations require a reason, lock current stock, check its version, and append immutable movements and audit records. Quantities are base units; decimal inputs retain six places.

Initial receiving discrepancies remain on their original goods-receiving records. This screen records subsequent stock events. Loss estimates use the immutable actual batch cost. Damage estimates represent exposure, not an additional posted operating expense; quarantining and subsequently disposing of the same goods must not be added together as separate losses in future reporting.

**Reduced-price sale** is for usable, non-expired goods with damaged packaging. It uses one selected batch and a configured base selling unit, requires an original price and reason, records original/reduced prices, actual cost and discount loss, and consumes the damaged bucket directly. It never makes damaged goods generally available. The current form records an exact cash payment for a walk-in customer. The usual below-cost permission and explicit approval remain mandatory. Expired goods and batches without a known actual unit cost cannot be sold. Goods sold as damaged can return only to damaged stock or disposal.

## Customer returns and exchanges

**Returns & refunds → Sales return / exchange** selects a posted original invoice and its actual batch allocations. Enter partial quantities or use **Return all remaining**. The database rejects quantities already returned, including competing concurrent requests. Choose sellable, damaged or discard for each batch. Expired/undated expiry-tracked goods cannot be restocked as sellable. Disposal records both receipt into damaged stock and removal, preserving the physical journey.

Credits use the original net invoice line amount, including its historical discounts/tax. Partial amounts round to four MMK decimals; the final remaining quantity receives the line's remaining credit so full returns cannot exceed the original total. Returned cost snapshots use the original sold batch unit cost, never current supplier pricing.

A return first reduces outstanding debt on its original invoice. **Refund customer** pays only the remainder supported by prior payment. For example, a 40,000 invoice paid 10,000 receives a 40,000 return credit, cancels 30,000 debt and refunds 10,000. **Credit customer account** keeps the resulting credit on that original account invoice. Applying that credit to a different invoice or later cashing out a previously retained credit is not implemented here.

An **exchange** links a return to a separately posted replacement invoice for the same customer. Create and collect the replacement sale in POS first, then select it when returning the original goods. The original return refund and replacement invoice payment remain separate, traceable transactions. Each replacement invoice can be linked once. This workflow does not silently swap original prices or costs or merge two invoices into an unaudited net adjustment.

## Supplier returns

**Purchase return** selects received batches from the original posted purchase and removes available or damaged goods from one warehouse. Quantities cannot exceed either current stock or the original purchase remaining for return. Supplier credit uses the original purchase amount per base unit, including discounts/tax, and its preserved currency/rate. Inventory leaves at actual landed cost; this may differ from supplier credit because transportation and other landed expenses are not automatically refunded.

Choose **Supplier credit** to reduce the payable or **Supplier refund** to also record the refundable amount already paid. Supplier refunds use the original transaction currency and rate. A refund does not create cash for an unpaid purchase.

## Safety and authorization

Review runs the full return calculation inside a PostgreSQL transaction and rolls it back, including temporary records and stock changes. Posting repeats the calculation and compares the reviewed credit/refund amounts. A changed result requires review again. Return/items, movements, credit, payment/allocation, approval and audit all commit together or roll back. Request UUIDs prevent duplicate posting; uncertain outcomes keep the exact request available for retry.

`damage.manage` controls stock exceptions; damaged sales additionally use `sales.create` and `payments.manage`. `returns.manage` controls returns. Purchase returns additionally require `purchases.view_cost`. Refunds/exchanges require `refunds.approve`, `payments.manage`, explicit confirmation and a reason. Approval records identify the authenticated approver and are immutable after consumption. Backend checks enforce every permission; only SUPER_ADMIN and STAFF_ADMIN roles exist. Cost-restricted staff do not receive actual loss estimates.

Posted returns, item costs, issues, movements and audit records are preserved. This phase provides original returns/refunds and linked exchanges; a general transaction-reversal UI remains separate work.

## Verification

Real PostgreSQL tests exercise preview rollback, eight injected return-write failures, duplicate retries, concurrent over-return prevention, stale stock versions, reserved-stock protection, partial credit refunds, original FIFO costs, reduced-price damaged sales, linked exchanges and supplier refunds at the original INR rate. Chrome/WebKit tests cover quarantine, missing stock, damaged checkout with below-cost approval, customer refunds, exchanges and supplier-credit returns through the real UI.
