# Phase 12 — batches and expiry

**Batches & expiry** lists batch number, product, manufacturing/expiry/received dates, received and available quantities, and historical cost totals. Open a batch for initial sellable, missing and damaged counts, cost breakdown and movement history. Costs require `finance.view_landed_cost`; all batch access requires `inventory.view` on the Go API.

Batch identity, dates and cost originate in goods receiving. Finalized batches cannot be edited or deleted; subsequent inventory adjustments change movement-controlled stock, not historical received quantities or costs. Entirely missing or damaged batches remain in history even with no available stock. A zero-sellable batch has no unit cost.

Expiry alerts use the Asia/Yangon business date: expired before today, due within 0–30 days, due in 31–60 days, current, or no expiry. Goods remain valid through the printed date. Date-boundary tests cover each transition. The dedicated `app.pos_eligible_stock` view excludes expired, uncosted, unavailable and expiry-required/undated goods. FIFO consumes eligible batches by received date and ID; the POS phase implements transactional allocation.

`GET /api/v1/batches` supports `q`, `expiry`, optional `batch_id`, and pagination. Existing FIFO and expiry indexes remain in use. The screen includes every historical batch rather than only those with current inventory rows.

Verified with `make check`, PostgreSQL integration tests and the real browser receiving → batches workflow. No historical costs or receiving records are rewritten by this migration.
