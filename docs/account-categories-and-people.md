# Bank, cash and other people's accounts

Accounts & balances now contains Bank Accounts, Cash Accounts, Other People's Accounts, and Needs classification. Bank/cash totals contain only business assets. Money owed to people and money people owe the business are shown separately, never netted against each other or customer invoice receivables.

## Setup and migration

Bank setup records Bank Name, Account Holder Name, Account Number and Opening Balance. Cash setup records Cash Account Name, Owner and Opening Balance. Opening funds create an immutable dated ledger entry in the same transaction as account creation. Bank names appear prominently with the holder underneath. Multiple accounts are supported; bank payment choices include a masked account-number suffix.

Migration 000043 preserves all existing entries and balances. Existing accounts explicitly labelled Cash are classified as cash; other nonempty bank fields are classified as bank. Accounts with no bank/type information remain under Needs classification and are unavailable for new payments until managed. Existing owner/holder fields remain blank until an administrator enters them; no names are invented. An account with history cannot change between bank and cash after classification; create a separate account instead.

Archive Account removes an account from new payment selections while retaining its balance and history. Restore Account makes it available again. Metadata changes remain versioned, permission-checked and audited.

## Supplier payments

Choose Bank Transfer or Cash first, then one paying account. Business choices are filtered by the method. Other people's accounts can fund the supplier directly, creating a payable without moving business cash. Cash requires the recipient's name in the form; it is recorded in payment and account history. The duplicate free-text bank-details field is removed. Old custom-method histories remain intact.

Account selectors throughout POS, customer collections, expenses, transport, refunds and creditor repayments filter business accounts by payment method. Database validation rejects mismatched cash/electronic accounts even if the form is bypassed. Source-linked historical reversals retain their original account.

## Other People's Accounts

Add a person such as Mother. Record:

- Borrow money: increases the receiving business account and money owed to that person.
- Lend money: decreases the paying business account and creates a separate personal receivable.
- Receive repayment of our loan: increases the receiving account and reduces the personal receivable, partially or fully.
- Gift received/given: moves money into/out of the selected account without creating debt.
- Repay: pays some or all of the amount owed to that person from a selected funded account.
- Third-party supplier/transport/expense payment: use its original business payment form; the person pays on behalf of the business and receives a corresponding payable.

Business customer collections remain attached to their invoices; they are not gifts or personal loans. Personal movements do not record operating profit or duplicate business expenses. Histories show cash movement, debt side, date, parties, reference and remaining balance. Corrections add linked opposite entries and preserve originals. Cash and liability checks prevent overdrafts or repayment beyond the applicable debt, including backdated changes.

The old `/creditors` bookmark opens the integrated Other People's Accounts category; it is no longer a separate sidebar page or Payment centre module.

## Dates and integrity

Record Account Transaction and Update actual balance show a date only. Time is captured automatically for ledger ordering; historical reconciliation rules remain enforced. All related entries, retry records and audit writes are atomic. Failed transactions roll back, repeated request IDs do not duplicate balances, and lending and borrowing remain separate even for the same person.
