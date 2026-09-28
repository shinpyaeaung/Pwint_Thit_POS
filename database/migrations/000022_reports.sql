-- All report amounts/quantities cross the JSON boundary as exact decimal strings.
CREATE FUNCTION app.report_decimal_row(document jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(jsonb_object_agg(key,CASE WHEN jsonb_typeof(value)='number' THEN to_jsonb(value #>> '{}') ELSE value END),'{}') FROM jsonb_each(document)
$$;
-- Return costing uses the same cumulative rounding as the authoritative P&L.
CREATE VIEW app.report_product_events AS
 WITH returned AS (
 SELECT i.id,i.product_id,r.returned_at,i.quantity,i.refund_mmk,b.unit_cost_mmk,
 sum(i.quantity) OVER(PARTITION BY b.id ORDER BY r.returned_at,r.id,i.id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS through_quantity,
 coalesce(sum(i.quantity) OVER(PARTITION BY b.id ORDER BY r.returned_at,r.id,i.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior_quantity
 FROM app.sales_returns r JOIN app.sales_return_items i ON i.sales_return_id=r.id JOIN app.sale_item_batches b ON b.id=i.sale_item_batch_id WHERE r.status='POSTED'
 )
 SELECT i.id,i.product_id,s.sold_at AS occurred_at,i.base_quantity AS quantity,i.total_mmk AS revenue_mmk,
 coalesce(c.amount,0) AS cogs_mmk,i.base_quantity<>coalesce(c.quantity,0) AS incomplete_cost
 FROM app.sale_items i JOIN app.sales s ON s.id=i.sale_id
 LEFT JOIN LATERAL (SELECT sum(b.total_cost_mmk) AS amount,sum(b.quantity) AS quantity FROM app.sale_item_batches b WHERE b.sale_item_id=i.id)c ON true WHERE s.status='POSTED'
 UNION ALL SELECT id,product_id,returned_at,-quantity,-refund_mmk,-(round(through_quantity*unit_cost_mmk,4)-round(prior_quantity*unit_cost_mmk,4)),false FROM returned;
CREATE INDEX report_movements_date ON app.inventory_movements(occurred_at,id);
CREATE INDEX report_damage_date ON app.damaged_products(occurred_at,id);
CREATE INDEX report_missing_date ON app.missing_products(occurred_at,id);
