# Phase 9 verification

Verified on 2026-09-25:

- `make generate` generated pgx/sqlc queries from the landed-cost SQL and migration 000013.
- `make check` passed Go race tests/vet and pnpm lint, TypeScript and production build. The existing shared-bundle size advisory remains; shipment UI is lazy-loaded.
- Formula tests cover quantity, purchase value, weight, carton quantity and manual allocation; the 120,000 + 80,000 = 200,000 example; actual unit cost 16,666.66666667 for 12 sellable units; reduced and zero sellable quantities; independent transport/expense totals; deterministic remainders; conservation over 1–100 item allocations; zero-cost goods; split-purchase rounding; and invalid, missing, duplicate, negative, NaN, excessive-precision and overflow input.
- Real PostgreSQL integration passed: historical foreign line conversions reconcile with purchase snapshots; active expenses exclude voided entries; costing uses purchase + transport + expenses; unit cost persists exactly; stale tokens roll back; staff preview and finalization permissions are enforced; concurrent finalization produces one snapshot/audit; finalized SQL rows and JSON snapshots reject edits/deletes; split shipments conserve a 0.0001-MMK purchase cost and invalidate earlier previews when shared source allocations change.
- All 14 real-stack Chromium tests passed. The shipment test now previews all five allocation methods, confirms exact landed/unit totals, finalizes, reloads the immutable result, checks fee controls disappear, and verifies unauthorized staff cannot see costing or read its API.
- Desktop finalized cost journey and mobile costing form/result were visually reviewed. The 375px width assertion passed.

- `make up` applied migration 000013 and rebuilt all services successfully. Local smoke checks passed for health, admin login/logout, the new permission catalog and shipment route; unauthorized costing returned 401 and an absent shipment returned 404 through the migrated API. No demonstration business data was created locally.

Automated business fixtures are isolated in disposable databases. Finalization does not receive goods or create stock/sales. The next receiving phase must reconcile confirmed sellable quantities and transfer finalized landed totals to batch costs; sales/profit must consume those preserved batch costs without a purchase-price fallback.
