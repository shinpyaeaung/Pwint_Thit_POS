# Permanent account deletion

Accounts & balances supports create, view, edit, archive/restore and permanent deletion of bank and cash accounts. Only Super Admin can permanently delete, including staff who have all configurable permissions.

Choose **Delete permanently** on an account card. Review the account balance and counts, type its exact account name, and enter a reason. This removes the database account and its ledger/payment history, including payments, invoice allocations, original/offset payment links, personal transactions and their corresponding debt entries. It disappears from account cards, history filters and new payment choices. Archived accounts can also be deleted.

This is an explicit user-approved exception to immutable financial history. Purchases, invoices, expenses, returns, physical inventory movements and finalized costs remain. Removing settlements can reopen outstanding invoices and change historical financial reports. Original document snapshots and security audit records remain. A minimal deletion receipt and erased request identifiers remain for audit and retry protection; deleted account creation/payment requests cannot recreate erased data.

Deletion uses one transaction, exact-row scoped trigger exceptions, and table locks that serialize against financial posting. Ordinary direct deletion and updates remain blocked. Audit failure rolls back every deletion and tombstone. A repeated successful request returns the original result. Changed account metadata or entries require a fresh review. Dependent reversals in another business account and deletion that would leave negative outstanding personal debt are blocked; resolve the linked repayments before retrying. No other account is silently erased.

API: `GET /api/v1/accounts/:id/delete-preview`, then `DELETE /api/v1/accounts/:id` with `request_id`, `fingerprint`, `confirmation` and `reason`. These routes enforce Super Admin independently of frontend controls.

Verification: full PostgreSQL integration suite, `make check`, and all 38 real-stack Chromium/WebKit browser cases passed. Tests cover cash/bank histories, expense original/offset payments, loans and linked repayments, authorization, stale confirmation, audit rollback, request replay, removal from UI/options after reload, and preservation of source documents. An initial browser run caught a post-delete preview refresh delay; excluding the deleted preview from invalidation fixed it, and the complete rerun passed.
