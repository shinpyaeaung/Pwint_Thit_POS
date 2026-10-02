-- name: ReportSupplierPayables :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
balances AS (
 SELECT s.id,s.purchased_at AS occurred_at,s.purchase_number AS reference,c.name AS party,s.due_date,t.total_mmk,
 coalesce((SELECT sum(a.applied_mmk) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.purchase_id=s.id AND p.status='POSTED' AND p.direction='OUT' AND p.paid_at<end_at),0) AS paid_mmk,
 coalesce((SELECT sum(i.credit_mmk) FROM app.purchase_returns r JOIN app.purchase_return_items i ON i.purchase_return_id=r.id WHERE r.purchase_id=s.id AND r.status='POSTED' AND r.returned_at<end_at),0) AS credits_mmk,
 coalesce((SELECT sum(a.applied_mmk) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id JOIN app.purchase_returns r ON r.id=a.purchase_return_id WHERE r.purchase_id=s.id AND r.status='POSTED' AND r.returned_at<end_at AND p.status='POSTED' AND p.direction='IN' AND p.paid_at<end_at),0) AS refunds_mmk,
 CASE WHEN s.purchased_at<start_at THEN 'OPENING' ELSE 'PERIOD' END AS invoice_period
 FROM app.purchases s JOIN app.suppliers c ON c.id=s.supplier_id JOIN app.purchase_totals t ON t.purchase_id=s.id CROSS JOIN dates WHERE (s.status='POSTED' OR EXISTS(SELECT 1 FROM app.purchase_reversals rev WHERE rev.purchase_id=s.id AND rev.reversed_at>=end_at)) AND s.purchased_at<end_at
),
filtered AS (
SELECT b.*,total_mmk-paid_mmk-credits_mmk+refunds_mmk AS outstanding_mmk,
 CASE WHEN due_date<end_on THEN 'OVERDUE' WHEN paid_mmk>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END AS payment_status
 FROM balances b CROSS JOIN dates WHERE total_mmk-paid_mmk-credits_mmk+refunds_mmk>0
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('outstanding_mmk',round(coalesce(sum(outstanding_mmk),0),4)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
