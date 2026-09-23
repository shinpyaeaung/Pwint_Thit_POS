# Phase 5 — Product module

This vertical slice connects PostgreSQL, typed sqlc/pgx queries, Gin permission policies, and the Phase 4 components. Products, catalog reference data, and packaging are real API-backed records. No sample data is inserted into the application database.

## User workflow

Open **Products** in the sidebar. Search by name, SKU, product barcode, or packaging barcode; filter by status, category and brand. Pagination runs on the server with selectable page sizes (10/20/50/100).

**Add Product** captures identity, optional category/brand/country/description, base stock unit, minimum stock, active status, and expiry tracking. The base packaging conversion is always 1. Add a Carton packaging row with 12 base units when the base is Bottle, then choose the appropriate purchase and sale defaults. Each product must have exactly one of each default.

Open a product to view all conversions, barcode values, defaults, status and metadata. Edit saves the complete product and packaging transactionally. If another user saved first, the API rejects stale changes; reload before editing again.

**Archive product** implements deletion without removing product identity or history. Archived products are inactive and appear only under the Archived list filter, but their details remain accessible. Their SKU and barcodes stay reserved. They cannot be edited through this module. Inactive products are distinct: they remain in the current catalog and may be reactivated by editing their status.

**Catalog setup** creates and edits category/brand names and active status, and adds unit definitions. Unit codes are permanent. Inactive category/brand references remain visible on existing products; select an active reference or clear it before saving a product edit. Catalog management opens in another tab from the product form; returning focus refreshes its choices.

## API and authorization

| Endpoint under `/api/v1` | Permission |
| --- | --- |
| GET `/products`, `/products/:id` | `products.view` |
| POST `/products` | `products.create` |
| PUT `/products/:id` | `products.update` |
| DELETE `/products/:id` | `products.delete` |
| GET `/catalog` | Any of product view/create/update or catalog management |
| POST `/catalog/categories`, `/catalog/brands`, `/catalog/units` | `catalog.manage` |
| PUT `/catalog/categories/:id`, `/catalog/brands/:id` | `catalog.manage` |

Staff using the management screens need `products.view` together with the respective mutation permission. Super Admin has full access. `Require` and `RequireAny` centralize Go policy decisions; UI hiding is only presentation. Mutations retain the existing Origin/header CSRF protection.

GET `/products` accepts `q`, `status` (`all`, `active`, `inactive`, `archived`), `category_id`, `brand_id`, `page` (1-based) and `page_size` (1–100). It returns `{products, total}` from one database snapshot, ordered by creation timestamp descending and ID for deterministic pages. Search uses literal substrings; `%` and `_` are not wildcard operators.

Create/update body example:

```json
{
  "sku": "TEA-001",
  "name": "Bottled tea",
  "barcode": "000123456789",
  "base_unit_code": "BOTTLE",
  "minimum_stock": "20.000000",
  "is_active": true,
  "tracks_expiry": false,
  "packaging": [
    {"unit_code":"BOTTLE","units_per_pack":"1","is_default_purchase":false,"is_default_sale":true},
    {"unit_code":"CARTON","units_per_pack":"12","barcode":"000123456790","is_default_purchase":true,"is_default_sale":false}
  ]
}
```

PUT also requires the current `version` string. DELETE accepts `{"version":"<current version>"}` and returns 204. Quantities are decimal strings, never JSON floating-point amounts. Optional empty values become SQL NULL. Minimum stock supports 14 whole digits and six decimal places; packaging ratios must be positive and fit the same precision. No silent rounding, exponent notation, NaN, or negative values is accepted.

## Integrity

Migration 000009 adds archive/version columns, indexes, case-insensitive SKU uniqueness, two permissions, and a shared barcode registry maintained by database triggers. Its primary key prevents duplicate scans across products and packaging even during concurrent requests. Existing legacy `products.manage` grantees receive the new archive/catalog grants once during migration.

SKUs are trimmed, case-insensitive identifiers of at most 100 ASCII letters/digits/dots/underscores/hyphens/slashes. Barcode strings preserve leading zeros and case; they allow at most 100 printable ASCII characters without whitespace. Separate product and packaging barcodes must be distinct.

Products and their packaging save in one transaction, with before/after audit records. A row lock and version check prevent lost updates. Base stock units cannot change after the product is referenced by purchases, sales, batches, damage or missing records; transaction lines already snapshot their packaging conversion. Changing catalog packaging never rewrites historical documents. Existing prices on retained packaging rows are preserved.

The migration deliberately fails on conflicting legacy SKUs/barcodes rather than silently choosing a product. Already applied migrations are unchanged.

## Scope boundaries

This phase implements catalog and packaging, not purchasing, stock receiving, inventory balances, batch costing, price management, supplier management or image uploads. Minimum stock is a threshold, not opening stock. Product Details explains that stock/batch information will come from the corresponding vertical slices. Financial cost/profit data is not exposed by these endpoints.

Substring search currently scans candidate products after filters. Category/brand/status and stable page ordering have indexes; add measured search optimization when catalog scale warrants it.
