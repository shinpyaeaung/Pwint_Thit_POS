# Six-phase redesign progress

## Phase 1 — audit and strategy

Inventory and strategy are recorded in [inventory.md](inventory.md) and [strategy.md](strategy.md). The original brief is preserved in [brief.md](brief.md).

Baseline `make check` passed (Go tests/race/vet, frontend lint, six unit tests, TypeScript and production build). The first browser run passed 36/38 cases; both engines rejected the purchase-correction test's host-generated payment timestamp as future-dated. A fixed historical date was also correctly rejected because payments against corrected values cannot precede the correction. The final fixture uses the database-authored `corrected_at` timestamp unchanged, avoiding clock skew and preserving microseconds and ledger chronology. No application rules changed. Final complete browser rerun passed all 38 Chromium/WebKit cases.

Phase 1 complete: `make check` passed again and the final real-stack run passed 34 existing + 4 account workflow cases (111.90 seconds). Sign-in now awaits the lazy destination and its initial dashboard query, preventing WebKit cancellation errors during immediate navigation. Phases 2–6 have not started.

The next baseline run passed both correction cases and exposed a concurrent aggregate-read race in Chromium's shipment journey: dashboard profit and the separate profit endpoint were read across another worker's posted sale. The assertion now retries the two independent reads for at most ten seconds, requiring exact agreement. This changes only the test's timing assumption, not either endpoint or financial calculation.

Visual baseline: reviewed the 1280×600 Accounts screenshot from the navigation test. Rounded/shadowed action pills, oversized account cards, 10–11px pale navigation labels and repeated shell branding reduce useful density. These observations are covered by the Phase 2 tokens and Phase 3 shell strategy.

## Phase 2 — shared design system (complete)

Implemented semantic neutral tokens, 4/6/8/10px radii, 13px base type, darker helper/label text, tabular figures, quiet ruled panels, compact controls and table rows, common filter/tab/table utilities, checkbox/radio focus and coarse-pointer targets. Shared page headers, states, badges and overlays use the same tokens. Buttons no longer scale or gain shadows on hover. Loading placeholders are static and reduced-motion/print behavior remains.

`make check` passed. Reviewed the generated component-library and modal screenshots: labels, exact decimal fields, table pagination, dialog boundaries and visible focus are clear. All 38 real-stack browser cases passed in 109.17 seconds. Removed two inert undefined shadow declarations found during source review; this does not change rendered appearance. Shell and cost-journey typography are scheduled for Phase 3, remaining page-level styling for Phase 5.

## Phase 3 — shell and core workflows (complete)

Introduced the PT red/yellow monogram, a 224px sidebar with preserved independent scrolling/pinned links, a 56px header, compact content margins and a restrained sign-in composition. Dashboard uses a ruled sales/profit strip, ledger-style monthly results, clear stock attention and a transaction list. Removed decorative gradients, sparkles, pulsing indicators and tiny labels. POS retains search/cart/checkout work areas with exact calculations, keyboard shortcuts and payment controls. Purchasing progress is a ruled step sequence; operational tables and cost journey use shared readable typography; core monetary columns are right aligned. Existing products, suppliers, customer and warehouse forms inherit the Phase 2 controls and overlays without workflow changes.

`make check` passed; all 38 browser cases passed in 107.43 seconds. Desktop/mobile dashboard and shell screenshots reviewed. Navigation now waits for loaded report results before leaving report routes, avoiding WebKit canceled-load errors. No backend, database, permission or mutation payload changes.

## Phase 4 — real-data visualizations (complete)

Added Recharts 3.10.1 with a lazy plot chunk and separate React runtime. Reusable horizontal comparisons cover dashboard monthly revenue/cost/profit, outstanding receivables/payables, finance period performance, expense categories and report amounts. Complete summary comparisons are explicitly distinguished from the first eight records on the current report page. No mixed-unit inventory totals or historical trend series are invented; unavailable trends/data are explained.

Original decimal strings remain the source for every visible exact value and tooltip. Number conversion is limited to SVG geometry. Negative and zero values remain distinct; unavailable/non-finite geometry is omitted. Charts provide keyboard support, approximate compact axis labels, exact-value disclosures, loading/empty states and a failure boundary that preserves the statement. Animations are disabled for stable reading and reduced-motion compatibility.

`make check` passed including ten frontend unit tests (four new cases covering precision, unavailable data, negative/zero values, complete-summary versus paginated scope and mixed units). Build chunks remain below 500kB: React runtime 218.75kB, entry 344.93kB, lazy chart 361.75kB (104.75kB gzip). Extended the real-stack report journey to check chart SVGs, page-scope disclosure, exact 123,456,789.1234 MMK display and keyboard interaction. All 38 browser cases passed in 105.41 seconds. The first run caught transient desktop-width overflow on mobile resize; plot containment fixes it. Reviewed desktop report charts with exact values. Production dependency audit: no known vulnerabilities. Final polish will widen the category-label gutter for long references.

## Phase 5 — system-wide refinement (complete)

Added shared view selectors with explicit pressed state for Accounts, Payment centre and report periods. Account balances now use ruled, responsive rows with grouped identity/actions and safe wrapping for large balances; loading/error states no longer display an invented zero total. Account history filters use a compact responsive grid. Customer/cargo payment balances now show labelled Total, Paid and Remaining rows with currency and right alignment.

Completed page-level typography/radius/surface normalization across administration, workspace, reports, assistant demo and remaining operational forms. Shared section headings and inline errors provide consistent hierarchy and feedback; report summaries use a ruled strip. Returns, expenses, creditor management, settings and help retain their established shared forms/tables and inherit the common controls, dialogs and states. Existing demo labelling and printable invoices are preserved.

`make check` passed. All mutations, historical amounts, permissions and workflow choices are unchanged. All 38 real-stack browser cases passed in 110.03 seconds.

Phase 5 browser review: the first run exposed assertions coupled to the former `.panel` account cards and slash-separated payment text. Updated them to locate semantic account articles and independently verify labelled Total/Paid/Remaining values. Financial/API assertions remain unchanged. Desktop Accounts screenshot reviewed: large balances fit, actions stay grouped and history filters align. Final rerun passed all 38 cases.
