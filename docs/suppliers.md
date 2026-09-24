# Supplier module — Phase 6

The Suppliers sidebar opens the list, with search by name, code, contact or phone; status and country filters; and server pagination. Add Supplier, Edit Supplier and Supplier Details use the same shared design system as Products.

## Records and lifecycle

Supplier fields: unique code, name, contact person, phone, address, two-letter country code, supplier type, payment terms, notes and active/inactive status. Codes are case-insensitively unique, including archived records. Different suppliers may have the same name. Phone numbers are text, preserving leading zeros and international prefixes. Optional blank fields are stored as null.

Deletion archives a supplier and marks it inactive; its code, purchases and audit trail remain available. Archiving does not cancel purchases or settle balances. Archived records cannot be edited or restored through this module. An inactive record can be edited or reactivated. Updates and archives require the last returned `version` string and use a row lock; stale submissions return 409. Each successful mutation and its before/after audit record commit together.

Names/contact people accept up to 200 UTF-8 bytes, codes 100 ASCII characters, phones/types 100 bytes, addresses/payment terms 2000 bytes and notes 4000 bytes. Codes allow letters, numbers, dots, underscores, slashes and hyphens, starting with a letter or number. Country codes are normalized to two uppercase letters. The server validates all limits, rejects unknown JSON fields and limits request bodies to 64 KiB.

## Permissions and API

All routes require a valid session. Super Admin has full access; Staff Admin grants are checked by centralized Go middleware.

| Method and path under `/api/v1` | Permission | Behavior |
| --- | --- | --- |
| GET `/suppliers` | `suppliers.view` | `{suppliers, total}`; `q`, `status=all/active/inactive/archived`, `country`, `page`, `page_size` |
| GET `/suppliers/:id` | `suppliers.view` | Full supplier contact record, including archived records |
| POST `/suppliers` | `suppliers.create` | Create; `code`, `name`, `is_active` required |
| PUT `/suppliers/:id` | `suppliers.update` | Replace editable fields; `version` required |
| DELETE `/suppliers/:id` | `suppliers.delete` | Archive; JSON body `{ "version": "1" }` |
| GET `/suppliers/:id/purchases` | `suppliers.view` and `purchases.view` | Paginated purchase history, including archived suppliers |

The UI needs `suppliers.view` together with update permission to load the edit screen and with create permission to show the saved details. Legacy `suppliers.manage` grants receive the four granular supplier grants once during migration. Later grant changes use the granular codes.

Page size is 1–100 (default 20); page is 1–100000. Supplier order is creation time descending, then UUID. History order is purchase time descending, then UUID. Counts and page rows are read from the same SQL snapshot.

## Purchase history

History reads actual purchase records; it is not sample frontend data. It shows purchase number, supplier invoice, purchase date, due date, status and item count. Draft, posted, cancelled and reversed documents remain identifiable by status. Only `purchases.view_cost` permits `total_original` in the API response; otherwise the field is omitted entirely. The server resolves this grant from PostgreSQL, never from the client's request.

Purchase totals sum existing line totals in PostgreSQL NUMERIC, including line discounts/taxes, and return decimal strings with the original currency. Totals are purchase amounts, not outstanding balances or landed costs; different currencies are not combined. No floating-point financial calculation is introduced.

Phase 7 adds purchase creation and ledger-based payable balances; see [purchasing](purchasing.md). Settlement entry and product–supplier assignments remain later modules. History is empty until purchases are recorded. Migration 000010 preserves existing records and fails on conflicting legacy codes rather than renaming suppliers silently.
