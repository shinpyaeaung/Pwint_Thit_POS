-- name: ReportDamage :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT d.id,'STOCK_ISSUE' AS source,d.occurred_at,p.name AS product,p.base_unit_code AS unit,b.batch_number,w.name AS warehouse,d.quantity,d.estimated_loss_mmk,d.reason,d.disposition
 FROM app.damaged_products d JOIN app.products p ON p.id=d.product_id LEFT JOIN app.batches b ON b.id=d.batch_id LEFT JOIN app.warehouses w ON w.id=d.warehouse_id CROSS JOIN dates WHERE d.occurred_at>=start_at AND d.occurred_at<end_at
 UNION ALL SELECT i.id,'RECEIVING',r.received_at,p.name,p.base_unit_code,i.batch_number,w.name,i.damaged_quantity,
 CASE WHEN b.finalized_at IS NOT NULL THEN round(i.damaged_quantity*b.actual_unit_cost_mmk,4) END,
 coalesce(i.notes,'Receiving discrepancy'),'QUARANTINE'
 FROM app.goods_receiving_items i JOIN app.goods_receiving r ON r.id=i.goods_receiving_id JOIN app.products p ON p.id=i.product_id
 LEFT JOIN app.batches b ON b.receiving_item_id=i.id JOIN app.warehouses w ON w.id=r.warehouse_id CROSS JOIN dates
 WHERE r.status='POSTED' AND i.damaged_quantity>0 AND r.received_at>=start_at AND r.received_at<end_at
 UNION ALL SELECT i.id,'SALES_RETURN',r.returned_at,p.name,p.base_unit_code,b.batch_number,w.name,i.quantity,round(i.quantity*sb.unit_cost_mmk,4),r.reason,i.disposition
 FROM app.sales_return_items i JOIN app.sales_returns r ON r.id=i.sales_return_id JOIN app.sales s ON s.id=r.sale_id
 JOIN app.sale_item_batches sb ON sb.id=i.sale_item_batch_id JOIN app.batches b ON b.id=sb.batch_id JOIN app.products p ON p.id=i.product_id JOIN app.warehouses w ON w.id=s.warehouse_id CROSS JOIN dates
 WHERE r.status='POSTED' AND i.disposition IN('DAMAGED','DISCARD') AND r.returned_at>=start_at AND r.returned_at<end_at

 UNION ALL SELECT i.id,'WAREHOUSE_TRANSFER',t.received_at,p.name,p.base_unit_code,b.batch_number,w.name,i.damaged_quantity,round(i.damaged_quantity*b.actual_unit_cost_mmk,4),coalesce(i.notes,'Transfer discrepancy'),'QUARANTINE' FROM app.stock_transfer_items i JOIN app.stock_transfers t ON t.id=i.transfer_id JOIN app.batches b ON b.transfer_item_id=i.id JOIN app.products p ON p.id=b.product_id JOIN app.warehouses w ON w.id=t.to_warehouse_id CROSS JOIN dates WHERE t.status='RECEIVED' AND i.damaged_quantity>0 AND t.received_at>=start_at AND t.received_at<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('estimated_loss_mmk',CASE WHEN count(*) FILTER(WHERE estimated_loss_mmk IS NULL)=0 THEN round(coalesce(sum(estimated_loss_mmk),0),4)::text END) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
