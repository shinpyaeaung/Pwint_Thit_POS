# Phase 18 — Operating expenses and profit

**Operating expenses** records rent, salaries, electricity, internet, fuel, marketing, warehouse expenses, maintenance and other operating expenses. Enter an incurred date, category, description, exact MMK amount and notes. Paid-now entries also record the payment method/reference and payment allocation atomically. Unpaid entries still count as incurred operating expenses; later expense settlement is outside this form.

Posted expense values are immutable. **Reverse incorrect expense** creates an immutable correction dated today and, for a recorded payment, a linked incoming offset. The original expense and payment remain unchanged. The account list displays the effective Reversed status and net paid amount. This is a correction of an incorrect entry, not a vendor-refund workflow. A reason and reversal/payment permissions are required. Identical retries cannot create duplicate expenses or offsets, and failures roll back all expense/payment/audit writes. Existing posted-document guards are unchanged.

**Expenses & profit** defaults to the current Myanmar month through today and supports date ranges. It calculates:

- Net sales revenue = posted sales minus posted sales-return credits.
- Cost of goods sold = original `sale_item_batches` landed-cost snapshots minus returned original batch cost. Cumulative rounding makes partial cost reversals sum to the original allocation.
- Gross profit = net sales revenue minus COGS.
- Net profit = gross profit minus recorded operating expenses, including dated expense reversal offsets.

Credit sales count as revenue when sold; collecting payment does not create another sale. Returns count on their return date whether settled by cash refund or account credit. Expense corrections do not erase earlier periods. All amounts remain PostgreSQL NUMERIC and decimal strings; supplier purchase price is never a profit fallback. If any sale lacks complete landed-cost allocations, the report withholds gross/net profit and identifies the incomplete count.

The report follows the requested sales/COGS/operating-expense formulas. Damage/missing estimates, stock-adjustment write-offs and supplier-return differences are not automatically posted as operating expenses. They remain separate operational records, preventing estimates or losses already absorbed into landed cost from being counted again. This is not a full general ledger or tax statement.

`expenses.manage` controls expense entry/history; `payments.manage` is additionally required for paid entries. Reversal also requires `transactions.reverse`. `finance.view_profit` controls the profit API and screen independently of expense entry. Only the two existing roles are used, with backend enforcement.

Verified coverage includes exact positive and negative profit, unpaid expenses, reversal/date effects, original return costs, unknown-cost protection, duplicate retries, authorization and rollback on audit failure. Browser tests exercise paid entry, correction and the profit statement in Chrome and WebKit.
