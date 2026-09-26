-- name: ExpensePost :one
SELECT app.expense_post(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: ExpenseReverse :one
SELECT app.expense_reverse(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: ExpenseCategories :one
SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]'::jsonb)::jsonb FROM app.expense_categories;
-- name: ExpensesList :one
WITH filtered AS(SELECT e.id,c.name AS category,e.description,e.incurred_at,e.amount_mmk::text AS amount_mmk,CASE WHEN EXISTS(SELECT 1 FROM app.expense_reversals r WHERE r.expense_id=e.id) THEN 'REVERSED' ELSE e.status END AS status,e.notes,u.display_name AS recorded_by,
 coalesce((SELECT sum(a.applied_mmk) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.expense_id=e.id AND p.status='POSTED' AND NOT EXISTS(SELECT 1 FROM app.expense_reversal_payments rp WHERE rp.original_payment_id=p.id)),0)::text AS paid_mmk
 FROM app.expenses e JOIN app.expense_categories c ON c.id=e.category_id JOIN app.users u ON u.id=e.recorded_by
 WHERE (sqlc.arg(search)::text='' OR strpos(lower(e.description||' '||c.name),lower(sqlc.arg(search)))>0)
 AND e.incurred_at>=coalesce(nullif(sqlc.arg(start_on)::text,'')::date,date_trunc('month',app.business_date())::date)::timestamp AT TIME ZONE 'Asia/Yangon'
 AND e.incurred_at<(coalesce(nullif(sqlc.arg(end_on)::text,'')::date,app.business_date())+1)::timestamp AT TIME ZONE 'Asia/Yangon'),page AS(SELECT * FROM filtered ORDER BY incurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'expenses',coalesce((SELECT jsonb_agg(to_jsonb(page) ORDER BY incurred_at DESC,id) FROM page),'[]'))::jsonb;
-- name: ProfitReport :one
WITH dates AS(SELECT coalesce(nullif(sqlc.arg(start_on)::text,'')::date,date_trunc('month',app.business_date())::date) AS start_on,coalesce(nullif(sqlc.arg(end_on)::text,'')::date,app.business_date()) AS end_on)
SELECT (app.profit_summary(start_on,end_on)||jsonb_build_object('expense_categories',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.name) FROM(SELECT c.name,round(sum(e.amount_mmk),4)::text AS amount_mmk FROM app.profit_expense_events e JOIN app.expense_categories c ON c.id=e.category_id WHERE e.occurred_at>=dates.start_on::timestamp AT TIME ZONE 'Asia/Yangon' AND e.occurred_at<(dates.end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' GROUP BY c.name)x),'[]')))::jsonb FROM dates;
