-- name: ReportMissing :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT d.id,'STOCK_ISSUE' AS source,d.occurred_at,p.name AS product,p.base_unit_code AS unit,b.batch_number,w.name AS warehouse,d.quantity,d.estimated_loss_mmk,d.reason
 FROM app.missing_products d JOIN app.products p ON p.id=d.product_id LEFT JOIN app.batches b ON b.id=d.batch_id LEFT JOIN app.warehouses w ON w.id=d.warehouse_id CROSS JOIN dates WHERE d.occurred_at>=start_at AND d.occurred_at<end_at
 UNION ALL SELECT i.id,'RECEIVING',r.received_at,p.name,p.base_unit_code,i.batch_number,w.name,i.missing_quantity,
 CASE WHEN b.finalized_at IS NOT NULL THEN round(i.missing_quantity*b.actual_unit_cost_mmk,4) END,
 coalesce(i.notes,'Receiving discrepancy')
 FROM app.goods_receiving_items i JOIN app.goods_receiving r ON r.id=i.goods_receiving_id JOIN app.products p ON p.id=i.product_id
 LEFT JOIN app.batches b ON b.receiving_item_id=i.id JOIN app.warehouses w ON w.id=r.warehouse_id CROSS JOIN dates
 WHERE r.status='POSTED' AND i.missing_quantity>0 AND r.received_at>=start_at AND r.received_at<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('estimated_loss_mmk',CASE WHEN count(*) FILTER(WHERE estimated_loss_mmk IS NULL)=0 THEN round(coalesce(sum(estimated_loss_mmk),0),4)::text END) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
