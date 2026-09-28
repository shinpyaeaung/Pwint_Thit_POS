-- name: ReportSales :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT e.id,e.occurred_at,e.event_type,CASE WHEN e.event_type='SALE' THEN s.invoice_number ELSE r.return_number END AS reference,
 coalesce(c.name,'Walk-in customer') AS customer,s.pricing_mode,e.revenue_mmk
 FROM app.profit_sales_events e LEFT JOIN app.sales_returns r ON e.event_type='RETURN' AND r.id=e.id
 JOIN app.sales s ON s.id=CASE WHEN e.event_type='SALE' THEN e.id ELSE r.sale_id END
 LEFT JOIN app.customers c ON c.id=s.customer_id CROSS JOIN dates
 WHERE e.occurred_at>=start_at AND e.occurred_at<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('revenue_mmk',round(coalesce(sum(revenue_mmk),0),4)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
