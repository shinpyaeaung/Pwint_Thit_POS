# Manual stock, returns and bank/cash accounts

## Stock without a purchase

Super Admin opens Inventory → Add existing stock. Select or create a warehouse, choose a product and packaging unit, enter quantity, actual cost per base unit, retail/wholesale prices per base unit, received date, expiry where required, and a reason. Products are created through Products first.

Posting creates an immutable manual-stock source, finalized batch, posted adjustment, stock movement and audit together. It updates warehouse prices for every configured package using exact decimal conversion. Zero cost must be explicitly entered; unknown cost is not assumed. Batch total cost is rounded to four MMK decimal places, with its unit cost derived from that stored total. No purchase or supplier debt is fabricated. FIFO sales, returns, expiry, stock reports, warehouse transfers and later warehouse pricing use this batch normally. Existing batch costs and invoice prices remain unchanged.

The backend and SQL enforce Super Admin for manual entries. Staff cannot bypass this by adding positive sellable/damaged quantities through stock adjustments, even if granted every configurable permission. Staff with the relevant permissions can still record valid receipts, returns and reservations. Later quantity corrections use controlled adjustments; posted manual entries cannot be overwritten.

## Returns

Returns & refunds retains original-invoice return quantities, historical cost and price, partial returns, sellable/damaged/discard disposition and approval controls. History now shows each returned product, quantity and unit alongside the credit and actual refund. Returns reduce outstanding invoice debt before cash is refunded. Choose the bank/cash account for a refund once accounts are configured. Stock, refund, account movement and audit commit together. Supplier returns continue to require original purchase lineage; manual stock has no supplier purchase to return against.

## Accounts and balances

Accounts & balances supports named banks such as KBZ and Yoma and cash accounts. All accounts in this version are MMK accounts. Foreign-currency payments retain their original amounts/rates and affect the account by their historically converted MMK amount. The total available balance is the exact sum of the account ledgers; negative balances remain visible.

Create an account, then use Update actual balance to record its opening balance. Account creation alone starts at zero. Existing payments are not silently assigned to new accounts or retroactively counted; enter the observed opening balance at the start of account tracking.

Use **Manage account** on a card to edit its name, bank and reference. Uncheck **Active account** and save to archive; check it again to restore. Archiving replaces destructive deletion: the card, balance and history remain available, but the account is removed from new-payment choices and cannot receive new manual entries. Source-linked business-expense reversals still return funds to the original account. Total account balance includes archived accounts, so archiving never hides money. Metadata changes are version-checked, retry-safe and audited atomically; original account identity and transaction rows cannot be deleted.

Once an account exists, new paid transactions require a selected account: POS, customer collections, supplier payments, cargo/additional-cost payments, refunds and paid business expenses. Expense reversals automatically restore the original account. Legacy payments with no assigned account remain unassigned on reversal. Installations without configured accounts retain their previous payment flow until accounts are set up.

External deposits record sender, date/time, amount, account and description. Personal expenses are separate outflows. Neither creates sales revenue or business operating expenses. Business expenses remain in Operating expenses; paid entries debit the selected account, while unpaid expenses still affect profit but do not move cash. Account payment rows are cash movements, not a second revenue/expense calculation.

Transaction entry has separate **Transaction date (Myanmar)** and **Transaction time (Myanmar)** controls, including seconds. Both are interpreted in UTC+06:30 regardless of the device timezone. Date, time and reason are required; future timestamps and entries inside reconciled periods remain rejected by the server.

Daily balance updates record the difference between the observed actual balance and the ledger balance at the selected Myanmar timestamp. They preserve all earlier rows and do not affect profit. Enter all transactions through that time before reconciling. New entries cannot be backdated into a reconciled period; record corrections after the latest balance observation. A later reconciliation can record an additional difference. Transaction histories show signed income/outflow and per-account running balances, with account, type and Myanmar date filters. History filters do not alter current-balance cards.

Manual deposits, personal expenses and balance adjustments can be corrected with an immutable opposite entry and a reason. Linked business payments are corrected from their original workflow, preventing a ledger-only correction from disagreeing with invoice debt. Retry identifiers, account locks and atomic audit writes protect against duplicate/concurrent postings.

`accounts.view` grants access to balances and the full sensitive history, including personal transactions. `accounts.manage` grants account/manual-entry creation and reversal. Both are automatically available to Super Admin; grant both when staff should manage this screen. Payment operators can select account names through a separate options endpoint without gaining access to balances or personal transactions. No payment gateway or bank connection is used.
