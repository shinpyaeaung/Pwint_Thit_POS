-- name: ReportMovements :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT m.id,m.occurred_at,p.name AS product,p.base_unit_code AS unit,b.batch_number,w.name AS warehouse,m.movement_type,m.sellable_delta,m.reserved_delta,m.damaged_delta,m.reason,u.display_name AS recorded_by
 FROM app.inventory_movements m JOIN app.batches b ON b.id=m.batch_id JOIN app.products p ON p.id=b.product_id JOIN app.warehouses w ON w.id=m.warehouse_id JOIN app.users u ON u.id=m.recorded_by CROSS JOIN dates WHERE m.occurred_at>=start_at AND m.occurred_at<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('movements',count(*)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
