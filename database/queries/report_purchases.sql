-- name: ReportPurchases :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
events AS (
 SELECT p.id,p.purchased_at AS occurred_at,'PURCHASE' AS event_type,p.purchase_number AS reference,p.supplier_id,p.currency_code,p.mmk_per_unit,t.total_original AS amount_original,t.total_mmk AS amount_mmk
 FROM app.purchases p JOIN app.purchase_totals t ON t.purchase_id=p.id WHERE p.status='POSTED' OR EXISTS(SELECT 1 FROM app.purchase_reversals rev WHERE rev.purchase_id=p.id)
 UNION ALL SELECT rev.id,rev.reversed_at,'REVERSAL',p.purchase_number,p.supplier_id,p.currency_code,p.mmk_per_unit,-a.amount_original,-a.amount_mmk
 FROM app.purchase_reversals rev JOIN app.purchases p ON p.id=rev.purchase_id JOIN app.purchase_amounts a ON a.purchase_id=p.id
 UNION ALL SELECT r.id,r.returned_at,'RETURN',r.return_number,p.supplier_id,p.currency_code,p.mmk_per_unit,-sum(i.credit_original),-sum(i.credit_mmk)
 FROM app.purchase_returns r JOIN app.purchase_return_items i ON i.purchase_return_id=r.id JOIN app.purchases p ON p.id=r.purchase_id WHERE r.status='POSTED' GROUP BY r.id,p.id
),
filtered AS (
SELECT e.*,s.name AS supplier FROM events e JOIN app.suppliers s ON s.id=e.supplier_id CROSS JOIN dates WHERE occurred_at>=start_at AND occurred_at<end_at
), page AS (SELECT * FROM filtered ORDER BY occurred_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('amount_mmk',round(coalesce(sum(amount_mmk),0),4)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY occurred_at DESC,id) FROM page),'[]'))::jsonb;
