# Carton and piece entry for warehouse dispatch

Goods to dispatch now offers a unit selector per source batch: Carton or the product's base unit (Piece, Bottle, etc.). Carton entry also supports loose individual units. Available stock and the dispatch preview show carton counts, loose units and the equivalent base quantity.

The conversion uses the source batch's recorded carton size, preserving its receiving/transfer history. A batch without a recorded carton size remains available in base units and explains why carton entry is unavailable. No carton size is guessed or substituted from another product/batch.

Switching modes preserves the exact total, including loose-unit remainders. BigInt fixed-point arithmetic matches the API's six-decimal quantity precision; invalid precision, overflow, zero/negative totals and quantities beyond available stock are rejected. No binary floating-point arithmetic is used for conversion.

The API continues to receive base-unit quantities. Existing stock version checks, transactional dispatch movements, retry protection, source costs, receiving and landed-cost allocation are unchanged. No database migration or existing-record conversion is required.

## Verification — October 31, 2026

`make check` passed: Go race/vet checks, lint, 13 frontend unit tests, TypeScript and production build. All 40 production-bundle Chromium/WebKit browser cases passed. The warehouse-transfer regression switches base/carton modes, checks over-dispatch rejection, combines cartons and loose units, verifies mobile width, dispatches 3 cartons of 2 bottles, and confirms source stock decreases from 10 to 4 while destination receipt creates 6 bottles at the expected landed cost. The initial mobile check exposed the fieldset's intrinsic minimum width; a scoped `min-w-0` constraint fixed the form without changing shared components. Exact conversion unit tests cover differing batch sizes, decimal precision, overflow and stock limits.

Only the frontend was deployed at http://localhost:8088. Nginx syntax, served bundle and API/database health were verified. Existing business records remain unchanged.
