-- name: ListBatches :one
WITH filtered AS (
 SELECT b.*,p.name AS product_name,p.sku,p.base_unit_code,r.received_quantity,r.damaged_quantity AS received_damaged_quantity,r.missing_quantity,
 app.expiry_status(b.expires_on,app.business_date()) AS expiry_status,
 coalesce((SELECT sum(i.available_quantity) FROM app.inventory i WHERE i.batch_id=b.id),0) AS available_quantity
 FROM app.batches b JOIN app.products p ON p.id=b.product_id JOIN app.goods_receiving_items r ON r.id=b.receiving_item_id
 WHERE (sqlc.arg(search)::text='' OR strpos(lower(p.name||' '||p.sku||' '||b.batch_number),lower(sqlc.arg(search)))>0)
 AND (sqlc.arg(expiry)::text='' OR app.expiry_status(b.expires_on,app.business_date())=sqlc.arg(expiry))
 AND (sqlc.narg(batch_id)::uuid IS NULL OR b.id=sqlc.narg(batch_id))
), page AS (SELECT * FROM filtered ORDER BY received_at,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('business_date',app.business_date(),'total',(SELECT count(*) FROM filtered),'batches',coalesce((SELECT jsonb_agg(
 jsonb_build_object('id',id,'product_name',product_name,'sku',sku,'base_unit',base_unit_code,'batch_number',batch_number,'received_at',received_at,'manufactured_on',manufactured_on,'expires_on',expires_on,'expiry_status',expiry_status,'received_quantity',received_quantity::text,'received_damaged_quantity',received_damaged_quantity::text,'missing_quantity',missing_quantity::text,'initial_sellable_quantity',sellable_quantity::text,'available_quantity',available_quantity::text,'finalized',finalized_at IS NOT NULL)
 || CASE WHEN sqlc.arg(costs)::boolean THEN jsonb_build_object('purchase_cost_mmk',purchase_cost_mmk::text,'transport_cost_mmk',transport_cost_mmk::text,'other_cost_mmk',other_cost_mmk::text,'total_cost_mmk',total_cost_mmk::text,'unit_cost_mmk',actual_unit_cost_mmk::text) ELSE '{}'::jsonb END ORDER BY received_at,id) FROM page),'[]'::jsonb))::jsonb;
