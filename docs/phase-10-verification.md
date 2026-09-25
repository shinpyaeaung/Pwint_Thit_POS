# Phase 10 verification

Verified on 2026-09-25:

- `make generate` generated typed, read-only journey/source queries. No financial schema migration or recalculation was needed.
- `make check` passed Go race tests/vet, TypeScript and production build. A component-export lint advisory was removed; the follow-up pnpm lint passed without warnings. The existing shared-bundle size advisory remains.
- `make test-integration` passed, including journey pagination, source exchange rates, partial shipment quantities, finalized allocation totals, and denied unauthorized history reads.
- All 15 Chromium tests passed. The new component test checks the supplied INR/MMK example, exact 40,000 MMK profit, -0.0001 MMK loss, zero profit, invalid/empty input, and mobile width. Shipment workflow tests now follow finalized journeys to Product Details and Purchase Details and verify the 60-of-100 partial allocation disclosure.
- Desktop and 375px mobile components were visually reviewed. The final mobile spacing was tightened, then the browser suite rerun. Decorative motion respects reduced-motion settings.

- `make up` rebuilt the local app with all services healthy. Smoke checks passed for health, admin login/logout, product/purchase journey reads and the UI library route; unauthorized journey reads returned 401. Existing business records were not changed.

The journey is shared across purchase, product, shipment and costing screens. Unknown values remain unavailable. Selling prices and profit are explicitly labelled unsaved scenarios, not invented business records. Finalized historical amounts and rates remain unchanged, and the backend protects financial reads. Test fixtures remain in disposable databases.
