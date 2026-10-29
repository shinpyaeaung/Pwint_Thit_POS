# Production-readiness review — 27 October 2026

This phase reviews the existing system and its cross-module integrity controls. It does not redesign the UI, add business modules, change accounting rules, or rewrite historical data. Existing uncommitted visual work is preserved separately from this phase's changes.

## Confirmed defects and fixes

| Priority | Finding | Fix and evidence |
| --- | --- | --- |
| High | A checkout can commit successfully but return truncated JSON or lose the connection while reading the response body. The frontend previously threw a plain exception, bypassing its uncertain-result guard and allowing the operator to abandon the original request. | The shared API client classifies unreadable success bodies as an uncertain API failure. It never automatically resubmits writes. Existing checkout and other guarded forms retain their original request identity. Unit tests reproduce both failure modes. A browser regression commits a real sale, truncates the response, retries the identical payload, and checks one stock decrement and one account credit. |
| High | Installed frontend development/build dependencies had seven registry advisories, including Vite file-access issues and source-map-js denial of service. | Vite 8.3.3, source-map-js 1.2.2, updated lockfile, and a narrowly scoped transitive override. The pinned pnpm version and existing release-age policy remain intact. |
| High | Go 1.27.1 and older backend dependencies were flagged by govulncheck. | Go 1.27.3 is required in go.mod and the container build. Updated x/net, x/text, quic-go and their required x/crypto/x/sync dependencies. The final scanner reports no vulnerabilities in imported packages. |
| Medium | Valid POS line totals can exceed the 14-digit input-price limit. Re-parsing those calculated totals during render could throw and blank the POS page. | Cart summation uses exact bigint arithmetic with a separate calculated-total width. Input limits and server validation remain unchanged. Regression tests cover large products, exact fractional sums, and invalid lines. |
| Medium | HTTP socket timeouts did not bound database query/pool work for every route. | Every request now has a 12-second context deadline, before the server's 15-second write timeout. Handler completion cancels the context. Existing shorter operation deadlines remain effective. |
| Medium | The served application lacked an explicit frame-embedding restriction. | Nginx now sets X-Frame-Options DENY and CSP frame-ancestors 'none', object-src 'none', base-uri 'self'. No inline-style or script-policy changes were introduced. |
| Low | Spreading RequestInit.headers silently dropped values supplied as a Headers object. | The API client uses the standard Headers API and preserves custom headers while setting the required request marker. Regression coverage includes a Headers object and JSON defaults. |

## Business and architecture review

| Area | Boundaries examined and covered by verification |
| --- | --- |
| Authentication and roles | Hashed session tokens, password hashing, secure-cookie production mode, origin/request-marker checks, database-backed login throttling, session expiry/revocation, backend permission checks, owner-only grant administration, permission-filtered responses. |
| Products and suppliers | Packaging conversion precision, catalog constraints, optimistic versions, archive/history behavior, search and pagination, permission enforcement. |
| Purchases and currencies | Exact decimal amounts, stored historical rates, partial supplier settlements, automatic identifiers, request deduplication, completed purchase revisions, dated reversal/correction reporting. |
| Shipments and landed costs | Quantity allocation limits, transport and separate expense liabilities, per-package fees, remaining historical purchase-cost allocation, exact remainder distribution, immutable finalized costing. |
| Receiving and inventory | Atomic cost/receipt/batch/movement posting, damaged/missing reconciliation, expiry, immutable movement-derived quantities, controlled manual adjustments, separate warehouse stock and product groups. |
| Warehouse transfers | Dispatch removes source availability, receipt adds destination stock once, destination landed cost includes cargo, source batch cost/expiry lineage is retained, cancellation uses controlled return movements. |
| Sales and customers | Transactional FIFO, mixed packaging, warehouse prices, customer special prices, explicit credit, below-cost approvals, atomic payments/audits, retry identity, own-invoice versus all-sales access. |
| Returns and refunds | Quantity bounds, original batch/cost linkage, sellable/damaged dispositions, refund permissions, linked exchanges, supplier returns, transaction rollback. |
| Finance and accounts | Ledger-derived balances, account/category matching, concurrent and backdated debit protection, separate personal receivables/payables, expense offsets, funding/reversal audit, account deletion safeguards and retry tombstones. |
| Reports and dashboard | Myanmar date boundaries, historical balance cutoffs, purchase corrections/reversals, movement-derived stock, actual landed-cost profit, incomplete-cost handling, sensitive-field permissions. |
| Frontend and UX | Strict TypeScript production compilation, lazy page loading, accessible overlays, mobile layouts, route permissions, query error handling, exact money previews, navigation and forms in Chrome/WebKit. |
| Database and deployment | Ordered checksummed transactional migrations, existing constraints/indexes, generated SQL bindings left intact, loopback service exposure, non-root application containers, production environment validation, health checks and graceful shutdown. |

Invoice checkout payment/debt snapshots are intentionally historical and explicitly labelled that way. Current debt remains in the customer/payment ledgers. They were not replaced with mutable invoice values. Account deletion remains the previously authorized exception to immutable payment history; this review did not delete any business records.

## Verification

- Baseline `make check`, full PostgreSQL integration, and all 38 real-stack browser cases passed before changes.
- Updated `make check` passed, including six new frontend unit tests, Go race tests, go vet, frontend lint, strict TypeScript compilation and the production build.
- Full PostgreSQL integration and all 38 real-stack browser cases passed against the changes. Browser tests include the response-loss retry regression in Chromium and WebKit.
- `make check` and all 38 browser cases also passed in an isolated copy of the exact staged release, excluding the preexisting visual edits.
- Final `pnpm audit`: zero advisories.
- Final `govulncheck` using v1.9.0: zero affected symbols/packages. One module-only advisory remains for the unimported, unmaintained `golang.org/x/crypto/openpgp` package (GO-2026-5932); there is no fixed version. The application uses x/crypto for password hashing, not OpenPGP.
- `scripts/verify-integrity.sql` runs in a read-only repeatable-read transaction and returns only counts. On the existing local database, all five checks returned zero violations: movement/stock mismatch, FIFO quantity mismatch, invoice total mismatch, negative historical cash positions, and negative personal-debt positions. This is a targeted consistency check, not proof of every possible data invariant.
- Tests create disposable databases. No real sales, payments, stock adjustments, or account deletions were used for verification.

## Remaining production work and limits

Local deployment was completed on 29 October from the isolated reviewed release (`0bdec4f`). Frontend, API and PostgreSQL are healthy at http://localhost:8088. The migration service completed, Nginx configuration and response headers passed verification, and the five read-only integrity checks still returned zero violations. The database volume was preserved.

This review does **not** certify a public production deployment. The repository currently supplies a local deployment foundation:

1. Configure and verify a real HTTPS domain, production origins/cookies, dedicated production credentials and restricted database roles/network access. The Compose database initialization role is also the API role; least-privilege production role separation is still needed.
2. Establish encrypted off-host automated backups, retention, and a tested restore procedure. Recovery objectives and backup destinations are not configured or verified by this phase.
3. Configure monitoring, alerting, log retention and operational ownership. No production uptime or incident-response service was tested.
4. Validate expected production data volume and concurrency with representative load tests. Existing indexes, pagination and local workflow tests are not a throughput benchmark. No speculative schema/index changes were made without measured evidence.
5. Review reverse-proxy login throttling before multi-client deployment: Gin intentionally trusts no forwarded client-IP headers, so requests through Nginx share the proxy's IP throttle bucket. Do not enable trust for arbitrary forwarded headers; a deployment must explicitly establish trusted proxy addresses and header sanitization.
6. No external penetration test, container-OS vulnerability scan, or exhaustive physical-business-data reconciliation was performed. Browser coverage is the implemented Chrome/WebKit suite, not every possible device or operation sequence.

No review or finite test suite can guarantee that all bugs have been eliminated. The results above describe the concrete fixes and exercised controls; unresolved operational requirements remain visible rather than being labelled production-ready.

Advisories: [source-map-js](https://github.com/advisories/GHSA-68fv-2mgg-jv7q), [Vite file access](https://github.com/advisories/GHSA-rq7h-c2jc-7f22), [unused OpenPGP package](https://pkg.go.dev/vuln/GO-2026-5932).
