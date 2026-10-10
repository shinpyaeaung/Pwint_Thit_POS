-- name: ReportCurrency :one
WITH bounds AS (SELECT sqlc.arg(start_on)::text::date AS start_on,sqlc.arg(end_on)::text::date AS end_on), dates AS (SELECT *,start_on::timestamp AT TIME ZONE 'Asia/Yangon' AS start_at,(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon' AS end_at FROM bounds),
events AS (
 SELECT p.id,p.purchased_at AS occurred_at,'PURCHASE' AS event_type,p.purchase_number AS reference,p.supplier_id,p.currency_code,p.mmk_per_unit,t.total_original AS amount_original,t.total_mmk AS amount_mmk
 FROM app.purchases p JOIN app.purchase_totals t ON t.purchase_id=p.id WHERE p.status='POSTED' OR EXISTS(SELECT 1 FROM app.purchase_reversals rev WHERE rev.purchase_id=p.id)
 UNION ALL SELECT c.id,c.recorded_at,'CORRECTION_BEFORE',p.purchase_number,(c.before_document->>'supplier_id')::uuid,c.before_document->>'currency_code',(c.before_document->>'mmk_per_unit')::numeric,-(c.before_document->>'total_original')::numeric,-(c.before_document->>'total_mmk')::numeric FROM app.purchase_corrections c JOIN app.purchases p ON p.id=c.purchase_id
 UNION ALL SELECT c.id,c.recorded_at,'CORRECTION_AFTER',p.purchase_number,(c.after_document->>'supplier_id')::uuid,c.after_document->>'currency_code',(c.after_document->>'mmk_per_unit')::numeric,(c.after_document->>'total_original')::numeric,(c.after_document->>'total_mmk')::numeric FROM app.purchase_corrections c JOIN app.purchases p ON p.id=c.purchase_id
 UNION ALL SELECT rev.id,rev.reversed_at,'REVERSAL',p.purchase_number,p.supplier_id,p.currency_code,p.mmk_per_unit,-a.amount_original,-a.amount_mmk
 FROM app.purchase_reversals rev JOIN app.purchases p ON p.id=rev.purchase_id JOIN app.purchase_amounts a ON a.purchase_id=p.id
 UNION ALL SELECT r.id,r.returned_at,'RETURN',r.return_number,p.supplier_id,p.currency_code,p.mmk_per_unit,-sum(i.credit_original),-sum(i.credit_mmk)
 FROM app.purchase_returns r JOIN app.purchase_return_items i ON i.purchase_return_id=r.id JOIN app.purchases p ON p.id=r.purchase_id WHERE r.status='POSTED' GROUP BY r.id,p.id
),
filtered AS (
SELECT e.currency_code AS id,e.currency_code,count(*) AS event_count,
 coalesce(sum(amount_original) FILTER(WHERE event_type='PURCHASE'),0) AS purchases_original,
 coalesce(-sum(amount_original) FILTER(WHERE event_type='RETURN'),0) AS returns_original,
 coalesce(-sum(amount_original) FILTER(WHERE event_type='REVERSAL'),0) AS reversals_original,
 coalesce(sum(amount_original) FILTER(WHERE event_type IN ('CORRECTION_BEFORE','CORRECTION_AFTER')),0) AS corrections_original,
 sum(amount_original) AS net_original,sum(amount_mmk) AS amount_mmk
 FROM events e CROSS JOIN dates WHERE occurred_at>=start_at AND occurred_at<end_at GROUP BY e.currency_code
), page AS (SELECT * FROM filtered ORDER BY currency_code LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'summary',(SELECT jsonb_build_object('amount_mmk',round(coalesce(sum(amount_mmk),0),4)::text) FROM filtered),'rows',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY currency_code) FROM page),'[]'))::jsonb;
