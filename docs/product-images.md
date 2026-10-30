# Product images and official sidebar branding

Product creation and editing support direct JPEG/PNG file selection, local preview, replacement and removal. Images appear in the catalog (including grouped variants), product details, POS search and the cart. No external image URL entry or Supabase setup is required.

Migration 000045 stores actual sanitized image bytes in `app.product_images` in PostgreSQL, so images persist with the existing database volume and are included in database backups. No uploaded files are written to a local upload directory. Catalog/POS JSON contains only an image content hash; clients obtain bytes from the authenticated product image endpoint. The original transparent official logo is a static application asset, separate from uploaded product photos.

Uploads are limited to 2 MiB, 4096 pixels on either side and 12 megapixels. The server validates and decodes actual JPEG/PNG content, then re-encodes it to remove metadata and appended content. Two decoding slots bound concurrent decoded memory. Multipart requests are read with strict size limits without temporary disk files. Nginx permits the multipart envelope; the API enforces the smaller file limit. Other formats need conversion before upload.

Product and image writes use the existing product create/update permissions, version lock and audit transaction. Ordinary JSON edits preserve images. Removal requires an explicit flag; replacement and removal cannot be requested together. A failed audit or stale update cannot partially change an image. Audit records contain the previous/new image hash rather than the binary file; replacing an image does not retain the previous photo bytes. Archiving a product retains its current photo.

GET `/api/v1/products/:id/image` requires a session and any of product view/create/update or sales create permissions. This supports cashiers without catalog access. Responses use private/no-store caching and MIME sniffing protection. POST/PUT product endpoints retain existing JSON compatibility and additionally accept multipart `product` JSON plus an optional `image` file.

The sidebar uses the supplied transparent Pwint Thit Distribution logo in the desktop sidebar and mobile navigation drawer. Existing drawer collapse/open behavior remains; the system has no separate desktop icon-only sidebar mode.

No inventory, costing, payment or financial rules change. Migration is additive and does not rewrite existing product/business records.

## Verification — October 30, 2026

- `make check`: Go race tests/vet, warning-free lint, 11 frontend unit tests, TypeScript and production build passed.
- `make test-integration`: full PostgreSQL suite passed, including actual image persistence, permission denial, normal edits retaining images, stale version rejection, audit-failure rollback, removal and replacement. Unit tests reject corrupt/unsupported/oversized images and verify metadata/payload stripping.
- Production real-stack browser suite: all 40 Chromium/WebKit cases passed (36 existing/image cases plus 4 account cases). New coverage exercises create, reload, ordinary edit, replacement, removal, catalog thumbnails, official logo and mobile navigation. Existing shipment/POS tests now verify actual image decoding for both owner and a sales-only cashier.
- Initial browser runs exposed shared test-account login throttling and a scroll assertion that ignored browser clamping. The image suite now uses its own seeded account; navigation checks compare against the legal scroll maximum and carry forward the restored position. Production authentication limits and navigation behavior were not weakened.
- Desktop/mobile screenshots inspected in Chrome and Safari. Uploaded test photos and transactions were confined to disposable databases.
- Migration 000045 and updated API/frontend deployed at http://localhost:8088. All services healthy; nginx syntax valid, logo HTTP 200, unauthenticated image HTTP 401. Existing-data integrity checks returned zero violations in all five categories before and after deployment.
