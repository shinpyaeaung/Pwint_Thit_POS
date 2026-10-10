-- name: ReportSupplierPayables :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
balances AS (
 SELECT s.id,(d->>'purchased_at')::timestamptz AS occurred_at,s.purchase_number AS reference,c.name AS party,(d->>'due_date')::date AS due_date,(d->>'total_mmk')::numeric AS total_mmk,
 (b->>'amount_paid_mmk')::numeric AS paid_mmk,(b->>'credits_mmk')::numeric AS credits_mmk,(b->>'refunds_mmk')::numeric AS refunds_mmk,(b->>'outstanding_mmk')::numeric AS corrected_outstanding_mmk,
 CASE WHEN s.purchased_at<start_at THEN 'OPENING' ELSE 'PERIOD' END AS invoice_period
 FROM app.purchases s CROSS JOIN dates CROSS JOIN LATERAL (SELECT app.purchase_record(s.id,end_at) d,app.purchase_balance(s.id,end_at) b) current JOIN app.suppliers c ON c.id=(d->>'supplier_id')::uuid
 WHERE (s.status='POSTED' OR EXISTS(SELECT 1 FROM app.purchase_reversals rev WHERE rev.purchase_id=s.id AND rev.reversed_at>=end_at)) AND (s.purchased_at<end_at OR d->>'correction_version'<>'0')
),
filtered AS (
SELECT b.*,corrected_outstanding_mmk AS outstanding_mmk,
 CASE WHEN due_date<end_on THEN 'OVERDUE' WHEN paid_mmk>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END AS payment_status
 FROM balances b CROSS JOIN dates WHERE corrected_outstanding_mmk>0
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('outstanding_mmk',round(coalesce(sum(outstanding_mmk),0),4)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
