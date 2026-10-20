# Accounts, payments and third-party debts

Every new money payment must identify a bank/cash account, or an eligible third-party creditor. Supplier, transport and operating-expense payments offer both choices. POS receipts and customer collections identify the receiving account. A single active account is selected automatically; with multiple accounts the user chooses one.

## Business cash versus another person's money

Create as many named accounts as needed in **Accounts & balances**, such as My Cash, Mother's Cash, KBZ and AYA. These represent money controlled by the business. Record opening funds as a dated external deposit; balances are always sums of immutable ledger entries. Account metadata can be edited and accounts archived/restored without deleting history.

If Mother uses her own money to pay for the business, add her in **Money owed to others** and choose **Another person pays — money owed to them** on the payment form. The supplier/provider/expense payment is settled and the same amount becomes a debt owed to Mother. No business account is deducted. Do not also record this as a business-account payment.

The creditor page shows net funding, net repayments, remaining debt and a dated payment history. Repay some or all of the debt from a selected funded account. A repayment reduces cash and the creditor debt together; it does not record a second expense. Mistaken repayments can be reversed with a reason and the reversal permission. Offsetting entries restore the original account and debt; originals remain immutable.

## Customer credit and collections

A customer credit sale creates an invoice receivable. Only money actually collected increases the chosen account. Partial collection reduces the invoice debt by the received amount; full collection settles it. Receivables remain in the customer ledger, separate from amounts owed to creditors, supplier invoices and transport providers.

## Validation and history

- New outgoing payments cannot overdraw the chosen account. Account locks serialize competing debits; backdated debits must also leave every subsequent recorded balance nonnegative.
- Repayments cannot exceed the creditor debt at the selected date or make a subsequent recorded liability negative. Reverse relevant repayments before reversing funding that has already been repaid.
- Every posted payment and its account/liability entries, source allocation, audit and request-retry records commit together. A failed write rolls back all changes. Retrying the same request does not duplicate balances; changing a completed request is rejected.
- Payment history includes payer, payee, method, account or creditor, amount, date and reference. Foreign source payments preserve their recorded exchange rate and exact MMK value.
- Archived accounts cannot receive new transactions. Source-linked corrections preserve the original account. Reconciled periods retain their existing restrictions.
- Existing historical payments and balances are preserved. Old unassigned payments are not silently assigned to an account; their source-linked reversals remain unassigned. Existing negative balances must be corrected by recorded funds before new outgoing payments can proceed.

## Technical source of truth

Migration 000042 extends `app.account_entries`: each row belongs to exactly one money account or creditor. A creditor repayment has two entries linked to the same payment: a cash decrease and a liability decrease. Partial unique indexes allow each side once. No mutable cached bank balance is stored. Customer invoice debt continues to derive from immutable sales, allocations and return history; third-party liabilities derive from creditor ledger rows.

Backend permissions control creditor creation (`accounts.manage`), creditor history (`accounts.view`), repayment (`accounts.view` and `payments.manage`) and repayment correction (also `transactions.reverse`). Funding options reveal names only to payment-authorized users.
