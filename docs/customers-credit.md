# Phase 16 — Customers and credit

Customers & credit supports customer creation/editing, retail/wholesale type, business/contact details, notes, active status, credit limit, purchase history, live balances and payment history. Deactivate records rather than deleting financial history. Optimistic version checks prevent lost customer and special-price updates.

Special prices are exact MMK amounts per product/selling unit. They override retail/wholesale pricing for the selected customer. The POS uses the customer's type as its initial pricing mode, refreshes special prices when the customer changes, and rechecks the authoritative price during checkout. Existing invoice snapshots never change. Below-cost approval still applies.

Customer balances come from posted invoices, payment allocations, returns and refunds. Paid means no positive outstanding amount; Overdue takes precedence for unpaid balances after the due date in Asia/Yangon; remaining balances are Partially Paid or Unpaid. Credit limits are checked at checkout while locking the customer. Existing invoices retain their original at-checkout payment snapshot; the customer account shows current balances.

Record payment against a selected invoice. Payments must be positive and no greater than its current outstanding balance. Payment, allocation and audit records are atomic. Concurrent collection is serialized, and identical request UUID retries cannot charge twice. Uncertain network outcomes preserve the payment form for an identical retry. All amounts use NUMERIC or decimal strings.

Customer management, special pricing and account history require `customers.manage`. Collection additionally requires `payments.manage`. POS can fetch the selected customer's selling prices with `sales.create`, without access to their account ledger. Financial cost/profit restrictions remain enforced.

Browser coverage includes customer editing, wholesale type, special unit pricing, a 500,000 MMK sale paid 300,000 with 200,000 outstanding, and subsequent collection through Paid status. Backend coverage includes permission denial, stale prices/versions, live balances, duplicate retries, concurrent overpayment prevention and audit-failure rollback. Payment history shows the latest 200 records; invoice history is paginated.
