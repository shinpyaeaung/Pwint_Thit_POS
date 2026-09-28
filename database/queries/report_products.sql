-- name: ReportProducts :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT p.id,p.sku,p.name AS product,p.base_unit_code AS unit,sum(e.quantity) AS quantity,sum(e.revenue_mmk) AS revenue_mmk,
 CASE WHEN bool_or(e.incomplete_cost) THEN NULL ELSE sum(e.cogs_mmk) END AS cogs_mmk,
 CASE WHEN bool_or(e.incomplete_cost) THEN NULL ELSE sum(e.revenue_mmk-e.cogs_mmk) END AS gross_profit_mmk,
 count(*) FILTER(WHERE e.incomplete_cost) AS incomplete_cost_lines
 FROM app.report_product_events e JOIN app.products p ON p.id=e.product_id CROSS JOIN dates
 WHERE e.occurred_at>=start_at AND e.occurred_at<end_at GROUP BY p.id
), page AS (SELECT * FROM filtered ORDER BY product,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('revenue_mmk',round(coalesce(sum(revenue_mmk),0),4)::text,'gross_profit_mmk',CASE WHEN coalesce(sum(incomplete_cost_lines),0)=0 THEN round(coalesce(sum(gross_profit_mmk),0),4)::text END,'incomplete_cost_lines',coalesce(sum(incomplete_cost_lines),0)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY product,id) FROM page),'[]'))::jsonb;
