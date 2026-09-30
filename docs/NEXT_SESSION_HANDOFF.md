# v1.2 planning handoff — baseline v1.1

## User intent: wait for the next prompt

The user plans to change almost the entire system after resetting Codex. They explicitly said **not to make those changes now**. The redesign requirements have not yet been provided. Read their next prompt before planning or implementing the redesign. Do not infer the new scope from previous phase requests or start another module automatically.

## Starting point

- Project: `/Users/shinpyaeaung/Desktop/Pwint_Thit_POS`.
- App: http://localhost:8088 (local Docker Compose stack).
- Branch: `main`; version baseline: `v1.1.0` release tag on GitHub. Future redesign work is v1.2 and awaits the next user prompt.
- Read `AGENTS.md` and `docs/Pwint_Thit_Distribution_Overall_System_Specification.md`. New user scope takes precedence over the existing phase grouping.
- Phases 1–20 were implemented and verified. This is the existing baseline, not a requirement to preserve the current UX in the upcoming redesign.
- Stack: React/Vite/TypeScript/Tailwind/shadcn/ui/Framer Motion/TanStack Query/Zustand; Go/Gin/PostgreSQL/pgx/sqlc. Use pnpm.

## Recent user concerns and fixes

The user finds the current system unfriendly and has reported sidebar jumping, apparently uneditable packaging/rate inputs, and blank POS selectors. They now want a broader redesign; the fixes below do not establish that all usability problems have been resolved.

- `6546f96`: scrolling sidebar, pinned Dashboard/Reports, business navigation, user guide at `/guide`, permission-aware home. Removed developer tools from the daily menu. Found and rebuilt an outdated local Docker deployment that lacked Dashboard/Reports routes and migrations.
- `c76f2ea`: remembers sidebar scroll position across navigation/reload and drawer reopening; clearly displays the fixed base packaging conversion; explains locked rates; preserves selected POS customer labels during search; labels POS warehouse/pricing selectors and explains missing warehouses and cart locking.
- The local DB had **zero active warehouses** when checked. No warehouse or sample stock was inserted. Existing setup is Shipments → Create shipment → Add warehouse, followed by cost finalization/receiving before POS sales. This awkward setup path is relevant to the redesign.
- `ef30a47`: Currencies & exchange rates accepts a pair such as **100 INR = 4450 MMK**. Backend exact rational arithmetic normalizes it to **44.5000000000 MMK per INR**. Raw quote inputs are included in audit data. New effective-time input supports multiple same-day quotes without overwriting history.
- Authorized users can type over a selected historical quote's rate in a new purchase; editing clears the quote reference and uses a custom transaction rate. MMK-to-MMK remains 1. Rate permission is still enforced on the backend.
- User guide: `docs/user-guide.md`; in-app guide: `frontend/src/pages/help/`.

## Data and financial constraints to review explicitly in any redesign

Preserve real records and historical purchase rates/batch costs. Use exact decimals and backend validation. Stock changes require movements; related stock, payment, financial and audit operations require transactions. Completed financial records use controlled reversals/voids, not deletion. Backend permissions remain authoritative. Only SUPER_ADMIN and STAFF_ADMIN exist. Light-only appearance is the current preference.

Do not reset the database, replace real data with fixtures, or assume permission to migrate/delete business history just because the user requests a broad redesign. Identify conflicts between new requirements and financial integrity before implementing major architectural changes.

## Verification and deployment

At `ef30a47`:
- `make check` passed (Go race tests/vet, frontend lint and build).
- `make test-integration` passed against PostgreSQL.
- `make test-e2e` passed: 24 browser tests, including Chromium/WebKit coverage.
- `make up` rebuilt the local stack; backend/frontend/PostgreSQL healthy. New currency fields verified in the deployed bundle.
- No outstanding known build/test failure. These checks do not prove every UX issue is resolved.

Run relevant checks after future changes. `make up` updates the local running app; Git commits/pushes alone do not. Do not remove database volumes. Keep credentials, `.env`, backups and generated build output out of Git. Keep sqlc-generated Go committed. User authorized committing/pushing verified completed work to origin.

## Suggested opening for the next session

Read this note and the repository instructions, inspect the current code, then use the user's new redesign prompt to establish scope. Do not treat previous UI choices or phase assignments as the new specification. Explain major changes before implementing them and preserve working business behavior unless the new requirements explicitly change it.
