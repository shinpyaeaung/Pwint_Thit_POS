-- name: ReportExpenses :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
filtered AS (
SELECT e.id,e.occurred_at,c.name AS category,coalesce(x.description,original.description) AS description,
 CASE WHEN r.id IS NULL THEN 'EXPENSE' ELSE 'REVERSAL' END AS event_type,e.amount_mmk
 FROM app.profit_expense_events e JOIN app.expense_categories c ON c.id=e.category_id LEFT JOIN app.expenses x ON x.id=e.id LEFT JOIN app.expense_reversals r ON r.id=e.id LEFT JOIN app.expenses original ON original.id=r.expense_id CROSS JOIN dates WHERE e.occurred_at>=start_at AND e.occurred_at<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('amount_mmk',round(coalesce(sum(amount_mmk),0),4)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
