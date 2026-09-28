-- name: ReportTransportation :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT t.id,coalesce(t.departed_at,t.created_at) AS occurred_at,s.shipment_number,t.stage_number,t.provider_name,t.start_location,t.destination,
 CASE WHEN s.costs_finalized_at IS NULL THEN 'PROVISIONAL' ELSE 'FINALIZED' END AS cost_status,
 t.transportation_fee_mmk,t.loading_fee_mmk,t.unloading_fee_mmk,t.other_fee_mmk,t.total_mmk
 FROM app.transportation_stages t JOIN app.shipments s ON s.id=t.shipment_id CROSS JOIN dates
 WHERE s.status<>'CANCELLED' AND coalesce(t.departed_at,t.created_at)>=start_at AND coalesce(t.departed_at,t.created_at)<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('transportation_fee_mmk',round(coalesce(sum(transportation_fee_mmk),0),4)::text,'loading_fee_mmk',round(coalesce(sum(loading_fee_mmk),0),4)::text,'unloading_fee_mmk',round(coalesce(sum(unloading_fee_mmk),0),4)::text,'other_fee_mmk',round(coalesce(sum(other_fee_mmk),0),4)::text,'total_mmk',round(coalesce(sum(total_mmk),0),4)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
