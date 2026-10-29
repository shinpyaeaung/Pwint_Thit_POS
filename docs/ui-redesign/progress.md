# Six-phase redesign progress

## Phase 1 — audit and strategy

Inventory and strategy are recorded in [inventory.md](inventory.md) and [strategy.md](strategy.md). The original brief is preserved in [brief.md](brief.md).

Baseline `make check` passed (Go tests/race/vet, frontend lint, six unit tests, TypeScript and production build). The first browser run passed 36/38 cases; both engines rejected the purchase-correction test's host-generated payment timestamp as future-dated. A fixed historical date was also correctly rejected because payments against corrected values cannot precede the correction. The final fixture uses the database-authored `corrected_at` timestamp unchanged, avoiding clock skew and preserving microseconds and ledger chronology. No application rules changed. Final complete browser rerun passed all 38 Chromium/WebKit cases.

Phase 1 complete: `make check` passed again and the final real-stack run passed 34 existing + 4 account workflow cases (111.90 seconds). Sign-in now awaits the lazy destination and its initial dashboard query, preventing WebKit cancellation errors during immediate navigation. Phases 2–6 have not started.

The next baseline run passed both correction cases and exposed a concurrent aggregate-read race in Chromium's shipment journey: dashboard profit and the separate profit endpoint were read across another worker's posted sale. The assertion now retries the two independent reads for at most ten seconds, requiring exact agreement. This changes only the test's timing assumption, not either endpoint or financial calculation.

Visual baseline: reviewed the 1280×600 Accounts screenshot from the navigation test. Rounded/shadowed action pills, oversized account cards, 10–11px pale navigation labels and repeated shell branding reduce useful density. These observations are covered by the Phase 2 tokens and Phase 3 shell strategy.
