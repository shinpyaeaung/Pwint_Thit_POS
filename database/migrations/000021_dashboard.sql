-- A single statement snapshot; financial visibility is supplied by central backend authorization.
CREATE FUNCTION app.dashboard(access jsonb) RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH day AS (SELECT app.business_date() AS d),
 summaries AS (SELECT app.profit_summary(d,d) AS today,app.profit_summary(date_trunc('month',d)::date,d) AS month FROM day),
 low AS (SELECT p.id,p.name,p.sku,p.base_unit_code AS unit,p.minimum_stock::text AS minimum,
 coalesce(sum(i.available_quantity),0)::text AS quantity
 FROM app.products p LEFT JOIN app.pos_eligible_stock i ON i.product_id=p.id
 WHERE p.is_active AND p.minimum_stock IS NOT NULL
 GROUP BY p.id HAVING coalesce(sum(i.available_quantity),0)<=p.minimum_stock),
 expiry AS (SELECT b.id,p.name,b.batch_number,b.expires_on,p.base_unit_code AS unit,sum(i.sellable_quantity)::text AS quantity
 FROM app.batches b JOIN app.inventory i ON i.batch_id=b.id JOIN app.products p ON p.id=b.product_id,day
 WHERE b.expires_on<=day.d+60 AND i.sellable_quantity>0 GROUP BY b.id,p.id),
 damaged AS (SELECT p.id,p.name,p.base_unit_code AS unit,sum(i.damaged_quantity)::text AS quantity
 FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id
 WHERE i.damaged_quantity>0 GROUP BY p.id),
 value AS (SELECT count(*) FILTER(WHERE b.finalized_at IS NULL OR b.actual_unit_cost_mmk IS NULL) AS incomplete,
 round(coalesce(sum(i.sellable_quantity*b.actual_unit_cost_mmk) FILTER(WHERE b.finalized_at IS NOT NULL),0),4)::text AS amount
 FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id WHERE i.sellable_quantity>0),
 recent AS (
 SELECT s.id,'Sale' AS kind,s.invoice_number AS label,s.sold_at AS occurred_at,t.total_mmk::text AS amount_mmk,'/sales/'||s.id AS href FROM app.sales s JOIN app.sale_totals t ON t.sale_id=s.id WHERE s.status='POSTED' AND (access->>'sales')::boolean
 UNION ALL SELECT p.id,'Purchase',p.purchase_number,p.purchased_at,t.total_mmk::text,'/purchases/'||p.id FROM app.purchases p JOIN app.purchase_totals t ON t.purchase_id=p.id WHERE p.status='POSTED' AND (access->>'purchases')::boolean
 UNION ALL SELECT e.id,'Expense',e.description,e.incurred_at,e.amount_mmk::text,'/expenses' FROM app.expenses e WHERE e.status IN('POSTED','REVERSED') AND (access->>'expenses')::boolean
 UNION ALL SELECT r.id,'Expense reversal',e.description,r.reversed_at,(-e.amount_mmk)::text,'/expenses' FROM app.expense_reversals r JOIN app.expenses e ON e.id=r.expense_id WHERE (access->>'expenses')::boolean
 UNION ALL SELECT r.id,'Sales return',r.return_number,r.returned_at,(-sum(i.refund_mmk))::text,'/returns' FROM app.sales_returns r JOIN app.sales_return_items i ON i.sales_return_id=r.id WHERE r.status='POSTED' AND (access->>'returns')::boolean GROUP BY r.id
), recent_page AS(SELECT * FROM recent ORDER BY occurred_at DESC,id LIMIT 8)
SELECT jsonb_build_object('business_date',day.d,'as_of',now())
 ||CASE WHEN (access->>'sales')::boolean THEN jsonb_build_object('sales',jsonb_build_object('today_mmk',today->'revenue_mmk','month_mmk',month->'revenue_mmk')) ELSE '{}'::jsonb END
 ||CASE WHEN (access->>'profit')::boolean THEN jsonb_build_object('profit',jsonb_build_object('today',today,'month',month)) ELSE '{}'::jsonb END
 ||CASE WHEN (access->>'inventory')::boolean THEN jsonb_build_object(
 'low_stock',jsonb_build_object('total',(SELECT count(*) FROM low),'items',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM(SELECT * FROM low ORDER BY name,id LIMIT 6)x),'[]')),
 'expiring',jsonb_build_object('total',(SELECT count(*) FROM expiry),'expired',(SELECT count(*) FROM expiry,day WHERE expires_on<day.d),'items',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM(SELECT * FROM expiry ORDER BY expires_on,id LIMIT 6)x),'[]'))) ELSE '{}'::jsonb END
 ||CASE WHEN (access->>'inventory')::boolean AND (access->>'cost')::boolean THEN jsonb_build_object('inventory_value',jsonb_build_object('amount_mmk',CASE WHEN value.incomplete=0 THEN value.amount END,'incomplete_batches',value.incomplete)) ELSE '{}'::jsonb END
 ||CASE WHEN (access->>'damage')::boolean THEN jsonb_build_object('damaged',jsonb_build_object('total',(SELECT count(*) FROM damaged),'items',coalesce((SELECT jsonb_agg(to_jsonb(x)) FROM(SELECT * FROM damaged ORDER BY name,id LIMIT 6)x),'[]'))) ELSE '{}'::jsonb END
 ||CASE WHEN (access->>'customers')::boolean THEN jsonb_build_object('customer_debt_mmk',(SELECT round(coalesce(sum(greatest(outstanding_mmk,0)),0),4)::text FROM app.customer_debts)) ELSE '{}'::jsonb END
 ||CASE WHEN (access->>'supplier_cost')::boolean THEN jsonb_build_object('supplier_debt_mmk',(SELECT round(coalesce(sum(greatest(outstanding_mmk,0)),0),4)::text FROM app.supplier_payables)) ELSE '{}'::jsonb END
 ||jsonb_build_object('recent',coalesce((SELECT jsonb_agg(to_jsonb(recent_page) ORDER BY occurred_at DESC,id) FROM recent_page),'[]'))
 FROM day,summaries,value
$$;
