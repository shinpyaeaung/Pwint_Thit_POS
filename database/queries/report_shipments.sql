-- name: ReportShipments :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT s.id,s.created_at AS occurred_at,s.shipment_number,s.start_location,w.name AS destination,s.status,s.shipped_at,s.arrived_at,
 (SELECT count(*) FROM app.shipment_items i WHERE i.shipment_id=s.id) AS product_lines,
 (SELECT count(*) FROM app.transportation_stages t WHERE t.shipment_id=s.id) AS stages,
 CASE WHEN s.costs_finalized_at IS NULL THEN 'PROVISIONAL' ELSE 'FINALIZED' END AS cost_status
 FROM app.shipments s JOIN app.warehouses w ON w.id=s.destination_warehouse_id CROSS JOIN dates WHERE s.created_at>=start_at AND s.created_at<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('shipments',count(*)::text,'received',count(*) FILTER(WHERE status='RECEIVED')::text,'in_transit',count(*) FILTER(WHERE status='IN_TRANSIT')::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
