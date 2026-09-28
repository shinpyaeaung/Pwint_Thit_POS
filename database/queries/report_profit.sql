-- name: ReportProfit :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
profit AS MATERIALIZED (SELECT app.profit_summary(start_on,end_on) AS document FROM dates),
filtered AS (
SELECT 'profit' AS id,document->>'sales_mmk' AS sales_mmk,document->>'returns_mmk' AS returns_mmk,document->>'revenue_mmk' AS revenue_mmk,document->>'cogs_mmk' AS cogs_mmk,document->>'expenses_mmk' AS expenses_mmk,document->>'gross_profit_mmk' AS gross_profit_mmk,document->>'net_profit_mmk' AS net_profit_mmk,document->>'incomplete_cost_sales' AS incomplete_cost_sales FROM profit
), page AS (SELECT * FROM filtered ORDER BY id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT document FROM profit),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY id) FROM page),'[]'))::jsonb;
