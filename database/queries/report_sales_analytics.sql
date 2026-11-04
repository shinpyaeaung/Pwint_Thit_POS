-- name: ReportSalesAnalytics :one
WITH dates AS (SELECT sqlc.arg(start_on)::text::date::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(sqlc.arg(end_on)::text::date+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at),
events AS MATERIALIZED (
 SELECT e.product_id,e.occurred_at,e.quantity,e.revenue_mmk FROM app.report_product_events e CROSS JOIN dates WHERE e.occurred_at>=start_at AND e.occurred_at<end_at
), products AS (
 SELECT p.id,p.sku,p.name AS product,p.base_unit_code AS unit,
 sum(greatest(e.quantity,0)) AS sold_quantity,-sum(least(e.quantity,0)) AS returned_quantity,sum(e.quantity) AS net_quantity,
 sum(greatest(e.revenue_mmk,0)) AS sales_mmk,-sum(least(e.revenue_mmk,0)) AS returns_mmk,sum(e.revenue_mmk) AS revenue_mmk
 FROM events e JOIN app.products p ON p.id=e.product_id GROUP BY p.id
), ranked AS (SELECT *,row_number() OVER(ORDER BY sold_quantity DESC,revenue_mmk DESC,id) AS rank FROM products),
page AS (SELECT * FROM ranked ORDER BY rank LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int),
daily AS (SELECT (occurred_at AT TIME ZONE 'Asia/Yangon')::date AS day,sum(revenue_mmk) AS revenue_mmk FROM events GROUP BY 1),
hourly AS (SELECT extract(hour FROM occurred_at AT TIME ZONE 'Asia/Yangon')::int AS hour,sum(revenue_mmk) AS revenue_mmk FROM events GROUP BY 1)
SELECT jsonb_build_object('total',(SELECT count(*) FROM ranked),'summary',(SELECT jsonb_build_object('sales_mmk',coalesce(sum(sales_mmk),0)::text,'returns_mmk',coalesce(sum(returns_mmk),0)::text,'revenue_mmk',coalesce(sum(revenue_mmk),0)::text) FROM ranked),
'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY rank) FROM page),'[]'),
'analytics',jsonb_build_object('top_products',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(t)) ORDER BY rank) FROM (SELECT * FROM ranked ORDER BY rank LIMIT 10)t),'[]'),
'daily',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(daily)) ORDER BY day) FROM daily),'[]'),
'hourly',(SELECT jsonb_agg(jsonb_build_object('hour',h::text,'revenue_mmk',coalesce(revenue_mmk,0)::text) ORDER BY h) FROM generate_series(0,23)h LEFT JOIN hourly ON hour=h)))::jsonb;
