-- Read-only diagnostics. Return counts only; never repair financial history.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '15s';
WITH movements AS (
 SELECT warehouse_id,batch_id,sum(sellable_delta) sellable,
        sum(reserved_delta) reserved,sum(damaged_delta) damaged
 FROM app.inventory_movements GROUP BY warehouse_id,batch_id
)
SELECT 'inventory_movement_mismatches' AS check_name,count(*) AS violations
FROM app.inventory i FULL JOIN movements m USING(warehouse_id,batch_id)
WHERE coalesce(i.sellable_quantity,0)<>coalesce(m.sellable,0)
   OR coalesce(i.reserved_quantity,0)<>coalesce(m.reserved,0)
   OR coalesce(i.damaged_quantity,0)<>coalesce(m.damaged,0);

SELECT 'posted_sale_fifo_quantity_mismatches' AS check_name,count(*) AS violations
FROM app.sale_items i JOIN app.sales s ON s.id=i.sale_id
WHERE s.status='POSTED' AND i.base_quantity<>(
 SELECT coalesce(sum(b.quantity),0) FROM app.sale_item_batches b WHERE b.sale_item_id=i.id);

SELECT 'posted_sale_snapshot_total_mismatches' AS check_name,count(*) AS violations
FROM app.sales s WHERE s.status='POSTED' AND s.invoice_document IS NOT NULL
AND (s.invoice_document->>'total_mmk')::numeric<>(
 SELECT coalesce(sum(i.total_mmk),0) FROM app.sale_items i WHERE i.sale_id=s.id);

SELECT 'negative_cash_ledger_positions' AS check_name,count(*) AS violations
FROM (SELECT sum(amount_mmk) OVER(PARTITION BY account_id ORDER BY occurred_at,sequence) balance
 FROM app.account_entries WHERE account_id IS NOT NULL) entries WHERE balance<0;

SELECT 'negative_person_debt_positions' AS check_name,count(*) AS violations
FROM (SELECT sum(amount_mmk) OVER(PARTITION BY creditor_id,debt_side ORDER BY occurred_at,sequence) balance
 FROM app.account_entries WHERE creditor_id IS NOT NULL) entries WHERE balance<0;
ROLLBACK;
