-- name: ReportInventory :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT b.id::text||':'||w.id::text AS id,p.sku,p.name AS product,p.base_unit_code AS unit,b.batch_number,w.name AS warehouse,b.expires_on,
 coalesce(sum(m.sellable_delta) FILTER(WHERE m.occurred_at<start_at),0) AS opening_sellable,
 coalesce(sum(m.sellable_delta) FILTER(WHERE m.occurred_at>=start_at),0) AS period_change,
 sum(m.sellable_delta) AS closing_sellable,sum(m.reserved_delta) AS closing_reserved,sum(m.damaged_delta) AS closing_damaged,
 sum(m.sellable_delta-m.reserved_delta) AS closing_available
 FROM app.inventory_movements m JOIN app.batches b ON b.id=m.batch_id JOIN app.products p ON p.id=b.product_id JOIN app.warehouses w ON w.id=m.warehouse_id CROSS JOIN dates
 WHERE m.occurred_at<end_at GROUP BY b.id,p.id,w.id
 HAVING sum(m.sellable_delta)<>0 OR sum(m.damaged_delta)<>0 OR bool_or(m.occurred_at>=start_at)
), page AS (SELECT * FROM filtered ORDER BY product,batch_number,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('stock_positions',count(*)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY product,batch_number,id) FROM page),'[]'))::jsonb;
