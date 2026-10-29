# Pwint Thit UI redesign — strategy and phase gates

The [user brief](brief.md) defines exactly six sequential phases. The current light-only appearance, brand red #BA0D0D and accent yellow #F7A712 are retained. Existing visual edits are included in the redesign scope; their starting patch is saved at `/tmp/pwint-ui-before-redesign.patch`. Backend, database, permissions, API contracts, exact calculations and mutation payloads are outside the redesign boundary.

## Phase 1 — audit and direction

The [surface inventory](inventory.md) covers every TSX page/component, including embedded forms and overlays. Route coverage follows `permissions/index.ts`, `App.tsx` and permission-filtered navigation. Detail/create/edit variants share the same modules: products, suppliers, purchases/corrections, shipments/costing, receipts, inventory/movements, customers and invoices. Additional routes include POS, transfers, warehouse prices, batches, stock issues, returns, central/supplier payments, accounts/legacy creditors, expenses/profit, reports/business data, currency settings, users/permissions, guide, component reference, status and the labelled assistant demo. Warehouses are managed through the existing shipment/receiving forms; no new warehouse workflow is introduced.

### Findings

- Shared components exist, but recent page-specific stone colors, gradients, 18px corners, shadows and oversized cards compete with the earlier neutral system. Dashboard and login have decorative treatment unrelated to purchasing or finance.
- Labels and helper text frequently use 9–11px type and pale stone colors. Table headers are low contrast, over-spaced uppercase text. Financial figures need stable alignment and consistent emphasis.
- The 64px header and repeated brand/version text consume operational space. Desktop navigation is functionally sound (pinned overview, independently scrolling modules, preserved scroll); keep those behaviors while simplifying its visual treatment.
- Every metric is treated as a card, while purchasing, cost statements and recent activity need rows, separators and clear reading order. POS must preserve a distinct working area for search, cart and payment.
- Page-level tables, tabs, native controls, inline alerts and optional sections bypass shared visual patterns. Standardize these without replacing their transaction/validation behavior.
- The dashboard has current day/month aggregates but no historical time series. Reports expose complete summary totals plus paginated rows. A chart of a table page must explicitly say it covers that page; it must never imply a full-period trend or sum mixed currencies/units.
- Existing Radix overlays, focus restoration, exact text decimal inputs, reduced-motion handling and permission gates are useful foundations. Preserve them and test keyboard/mobile behavior after restyling.

### Visual direction

Use a compact, editorial operational workspace: quiet warm-white surfaces, charcoal text, ruled tables, precise red accents and restrained yellow warnings. Identity comes from the PT monogram, section hierarchy, transaction references and well-aligned financial information. No decorative gradients, pulsing live badges, floating card effects or ornamental sparkles.

Tokens: Inter 13px body, 12px labels/help (minimum), 22–24px page title, tabular financial figures; 4px spacing grid; 6px controls, 8px panels, 10px dialogs; 36px desktop controls with 40px touch targets on coarse pointers; 1px neutral borders; shadows only for floating overlays. Focus uses a clearly visible red outline, with textual status labels rather than color alone. Data tables scroll within labelled regions on small screens. Actions wrap instead of clipping.

Layout families: record lists use a header, quiet filter toolbar and ruled table; operational forms use labelled sections and optional details; transactions use a summary rail plus chronological/cost details; POS keeps two work areas; finance uses ledger statements; dashboard uses a compact KPI strip, operational exceptions and recent records. One language, adapted to each workflow.

### Chart/data policy

Use only existing permission-filtered responses. Retain exact strings for all displayed money and financial operations; floating-point values are permitted only for chart geometry, never for accounting. Expose exact values in accessible tables/tooltips. Display null/incomplete costs as unavailable, retain negative values, label units and date scope, and avoid fictitious comparisons. Do not manufacture prior-period data from recent transactions or a single report page.

## Sequential implementation and validation

| Phase | Deliverable | Gate |
| --- | --- | --- |
| 1 | Complete source inventory, findings, direction and data policy | Baseline `make check` and real-stack browser suite; review route coverage |
| 2 | Central tokens and reusable controls, tables, overlays, states | `make check`, real-stack browser suite, component/mobile screenshots |
| 3 | Application shell, login/home, dashboard composition and operational pages | `make check`, real-stack workflow suite, desktop/mobile visual review |
| 4 | Accessible real-data dashboard/report/profit charts | Geometry/data unit tests, `make check`, real-stack chart/filter/permission checks |
| 5 | Remaining finance, payments, returns, administration and all legacy styling | Whole-source consistency inspection, `make check`, real-stack suite |
| 6 | Final accessibility/responsive polish, visual review and release | Full checks, integration, browser suite, production container and health verification |

Each phase is committed and pushed only after its gate passes. This document records strategy; implementation completion is recorded separately in `progress.md` with evidence.

### Component migration boundaries

- Phase 2 owns `index.css`, UI primitives and `components/shared`: visual tokens, table density, readable labels, common form and overlay treatment. Preserve all component signatures and accessibility semantics.
- Phase 3 owns shell, sign-in/workspace, dashboard composition, operational form/list/detail families, cost journey and POS. Purchasing progress becomes a ruled step sequence; stock and financial columns align consistently. Warehouse management remains in its existing screens.
- Phase 4 introduces one lazy-loaded chart component backed by the existing aggregate contracts. Dashboard and finance compare monthly/current-period amounts; report charts use complete money summaries and explicitly disclose missing historical series. Recharts references: [responsive sizing](https://recharts.github.io/api/ResponsiveContainer/) and [keyboard accessibility](https://github.com/recharts/recharts/wiki/Recharts-and-accessibility).
- Phase 5 owns remaining admin, finance, payments, returns, settings, reports and help surfaces. Account selection and history filters need compact grid layouts; account balances must wrap without clipping. All numeric table columns should be right aligned.
- Phase 6 inspects every inventoried surface after migration and checks global visual rules against source, automated browser journeys and saved desktop/mobile screenshots. Existing printable invoices retain their print-specific behavior.
