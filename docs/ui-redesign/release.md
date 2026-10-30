# Pwint Thit UI redesign — release review

Implemented the [six-phase brief](brief.md) in order. See [strategy](strategy.md), [initial surface inventory](inventory.md), and [phase evidence](progress.md).

## Delivered

| Phase | Result | Commit |
| --- | --- | --- |
| 1 | Audit of 78 original page/component files, visual direction and data policy; reliable browser baseline | `f2becff` |
| 2 | Central tokens, readable labels, compact controls/tables, consistent states and accessible overlays | `91f0b48` |
| 3 | PT identity, compact shell, sign-in, dashboard, purchasing progress, POS and operational screens | `4755de2` |
| 4 | Real-data dashboard/report/profit charts, exact values, signed/unknown data handling, lazy loading | `d282da6` |
| 5 | Account rows, labelled payment balances, shared view selectors, remaining page/form consistency | `4ea0a63` |
| 6 | Final source/visual review, production-bundle browser gate, integration and deployment | Final release commit |

The system remains light-only with brand red #BA0D0D and yellow #F7A712. Existing page/component surfaces now total 83, including the reusable chart and view/balance components. Tables scroll inside their labelled regions on narrow screens. Navigation retains permission filtering, pinned overview/help, independent scrolling and restored position. Dialog focus trapping/return, busy protection, keyboard shortcuts, exact decimal entry and printable invoices remain.

## Data and business boundaries

No database migrations, production API contracts, authorization rules, transaction payloads, ledger calculations or historical records were changed. Backend changes are confined to test infrastructure/fixtures. No production accounts, stock or transactions were created for UI verification.

Charts consume existing permission-filtered responses. Displayed money and tooltips retain original decimal strings; floating-point conversion is restricted to drawing coordinates. Unavailable costs are not zero. Negative values remain signed. Current-page report comparisons explicitly disclose their scope and do not masquerade as period totals. Existing APIs do not provide historical trend series: the interface explains that limitation. The existing assistant remains clearly labelled as a demo.

## Verification

- Every completed phase passed `make check` and all 38 real-stack Chromium/WebKit cases after its fixes.
- Final `make check`: passed Go race tests/vet, frontend lint, ten unit tests, TypeScript and production build.
- Complete PostgreSQL integration suite: passed after stabilizing current-time account fixtures against the database clock. Deliberate future-date rejection tests remain.
- New `make test-e2e-production` serves compiled production bundles against the real API and disposable PostgreSQL databases. Browser workers are capped at four to respect the server's four concurrent password-hashing slots.
- Browser coverage includes authentication/permissions, product/supplier CRUD, historical purchasing/corrections, shipments, costing/receiving, stock movements/transfers, POS/credit/payments/returns, accounts/reconciliation/deletion, reports/date filters, exact chart values, keyboard interaction, mobile overflow, dialog bounds and focus restoration.
- Source consistency scan: no decorative gradients, sub-12px utility text, large 2xl corners, local stone palette or unused entrance animations remain.
- Palette measurements on white: body text 17.49:1, muted text 6.59:1, primary red 6.66:1. Yellow chart highlights have a dark boundary (5.24:1). These are targeted checks, not a formal accessibility certification.
- Production dependency audit: no known vulnerabilities. Production build has no oversized-chunk warning; chart code is loaded separately (~105kB gzip).
- Read-only existing-database diagnostics: zero inventory/movement mismatches, FIFO quantity mismatches, invoice-total mismatches, negative cash positions or negative personal-debt positions.

## Final release — October 30, 2026

All 38 compiled-production Chromium/WebKit cases passed in 121.69 seconds against a fixed build. Full PostgreSQL integration and final `make check` passed. The frontend image is deployed at **http://localhost:8088**. Frontend, API and PostgreSQL are healthy; the existing API/database containers and data volume were preserved. Live Chrome smoke checks verified sign-in rendering, script execution, mobile width and API health without signing in or changing business data. Nginx syntax, HTTP 200, no-cache and existing security headers were verified.

Representative reviewed captures are `/tmp/pwint-redesign-live-login.png`, `/tmp/pwint-dashboard-desktop.png`, `/tmp/pwint-dashboard-mobile.png`, `/tmp/pwint-reports-webkit-mobile.png`, `/tmp/pwint-navigation-chromium-desktop.png` and `/tmp/pwint-accounts-chromium.png`. Browser fixtures contain disposable data only. All six phases are complete; the six phase commits are pushed to GitHub origin.

## Scope limits

No historical trend endpoint was invented, and no unrelated business module was added. Automated workflows and representative desktop/mobile screenshots verify the redesign; this does not replace user acceptance testing of every possible record combination or a formal assistive-technology audit. Public hosting still needs the deployment requirements recorded in [the production-readiness review](../code-review-2026-10-27.md), including HTTPS, backup restoration, monitoring and representative load testing.
