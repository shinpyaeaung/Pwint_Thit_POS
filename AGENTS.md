# Pwint Thit development rules

Read `docs/Pwint_Thit_Distribution_Overall_System_Specification.md` as the project source of truth.
The user's current phase scope takes precedence over the document's suggested phase grouping.
Phases 1–12 are verified, including product/catalog, suppliers, purchasing, shipments, landed-cost allocation the shared Cost Journey UI, goods receiving, movement-controlled inventory, and batch/expiry history. Selling-price/profit scenarios are explicitly unsaved estimates, not recorded sales. Preserve historical rates, exact amounts, ledger-based payment status and immutable finalized costing snapshots. Receiving reconciles confirmed sellable quantities and transfers landed totals into batch costs. All inventory changes must originate from immutable movements or controlled adjustments; sales/profit must never fall back to supplier purchase price. Wait for the user’s next phase scope before starting another module. Keep the light-only appearance; the user rejected theme switching. Use pnpm. Do not start unrelated business modules.

Build each subsequent module vertically: database → API → backend tests → UI → integration → feature tests.
Use the agreed React/Vite/TypeScript/Tailwind/shadcn/ui/Framer Motion/TanStack Query/Zustand and Go/Gin/PostgreSQL/pgx/sqlc stack.
Use pnpm for all JavaScript dependency management and commands; do not use npm or npx. Keep the pinned packageManager version and pnpm-lock.yaml in sync.
Do not add Redis without a demonstrated technical need.
Explain any proposed change to important business rules before implementing it.
Preserve historical exchange rates and batch costs; MMK is the base currency.
Use exact decimal calculations for money; do not use binary floating point for financial logic.
There are only SUPER_ADMIN and STAFF_ADMIN roles. Enforce permissions on the backend.
Use transactions for related stock, financial, payment, and audit writes. Preserve completed records with reversals/voids.
Do not commit secrets or generated build output. Keep sqlc-generated Go files committed; regenerate from SQL rather than editing them.
Run `make check` and the real-stack browser test for relevant changes. Report any unverified requirement honestly.

After completing and verifying each phase, commit and push that phase to the GitHub origin. The user explicitly authorized this workflow. Keep secrets, local credentials, and build artifacts out of Git.
