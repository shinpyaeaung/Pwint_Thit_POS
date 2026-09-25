-- name: POSProducts :one
SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)::jsonb FROM (
 SELECT p.id,p.name,p.sku,p.barcode,p.base_unit_code,p.version::text,
 coalesce((SELECT sum(available_quantity)::text FROM app.pos_eligible_stock i WHERE i.product_id=p.id AND i.warehouse_id=sqlc.arg(warehouse_id)::uuid),'0') AS available_quantity,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('unit_code',u.unit_code,'units_per_pack',u.units_per_pack::text,'barcode',u.barcode,'retail_price_mmk',u.retail_price_mmk::text,'wholesale_price_mmk',u.wholesale_price_mmk::text,'is_default_sale',u.is_default_sale) ORDER BY u.is_default_sale DESC,u.unit_code),'[]'::jsonb) FROM app.product_units u WHERE u.product_id=p.id) AS packaging
 FROM app.products p WHERE p.is_active AND p.archived_at IS NULL AND (sqlc.arg(search)::text='' OR strpos(lower(p.name||' '||p.sku),lower(sqlc.arg(search)))>0 OR p.barcode=sqlc.arg(search) OR EXISTS(SELECT 1 FROM app.product_units u WHERE u.product_id=p.id AND u.barcode=sqlc.arg(search)))
 ORDER BY (p.barcode=sqlc.arg(search) OR EXISTS(SELECT 1 FROM app.product_units u WHERE u.product_id=p.id AND u.barcode=sqlc.arg(search))) DESC NULLS LAST,p.name,p.id LIMIT 50
) x;
-- name: POSWarehouses :one
SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]'::jsonb)::jsonb FROM app.warehouses WHERE is_active;
-- name: POSCustomers :one
SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)::jsonb FROM (SELECT id,code,name,phone,customer_type,credit_limit_mmk::text FROM app.customers WHERE is_active AND (sqlc.arg(search)::text='' OR strpos(lower(code||' '||name||' '||coalesce(phone,'')),lower(sqlc.arg(search)))>0) ORDER BY name,id LIMIT 50) x;
-- name: POSCreateCustomer :one
WITH created AS (INSERT INTO app.customers(code,name,phone,customer_type,credit_limit_mmk) SELECT 'C-'||gen_random_uuid(),d->>'name',nullif(d->>'phone',''),d->>'customer_type',(d->>'credit_limit_mmk')::numeric FROM (SELECT sqlc.arg(data)::jsonb d) src RETURNING *), audit AS (INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) SELECT sqlc.arg(actor)::uuid,'customers.create','customers',id,to_jsonb(created) FROM created)
SELECT id FROM created;
-- name: POSPrices :exec
SELECT app.pos_prices(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid);
-- name: POSCheckout :one
SELECT app.pos_public_document(app.pos_sale(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid,sqlc.arg(discounts)::boolean,sqlc.arg(below_cost)::boolean,sqlc.arg(preview)::boolean),sqlc.arg(costs)::boolean,sqlc.arg(profits)::boolean)::jsonb;
-- name: POSInvoice :one
SELECT (jsonb_build_object('id',s.id,'invoice_number',s.invoice_number,'sold_at',s.sold_at,'status',s.status,'cashier',u.display_name)||app.pos_public_document(s.invoice_document,sqlc.arg(costs)::boolean,sqlc.arg(profits)::boolean))::jsonb FROM app.sales s JOIN app.users u ON u.id=s.created_by WHERE s.id=sqlc.arg(id)::uuid AND s.invoice_document IS NOT NULL AND (sqlc.arg(all_sales)::boolean OR s.created_by=sqlc.arg(actor)::uuid);
-- name: POSSales :one
WITH filtered AS (SELECT s.id,s.invoice_number,s.sold_at,s.invoice_document->>'customer_name' AS customer_name,s.invoice_document->>'total_mmk' AS total_mmk,s.invoice_document->>'paid_mmk' AS paid_mmk,s.invoice_document->>'outstanding_mmk' AS outstanding_mmk FROM app.sales s WHERE s.invoice_document IS NOT NULL AND (sqlc.arg(search)::text='' OR strpos(lower(s.invoice_number||' '||(s.invoice_document->>'customer_name')),lower(sqlc.arg(search)))>0)),page AS (SELECT * FROM filtered ORDER BY sold_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'sales',coalesce((SELECT jsonb_agg(to_jsonb(page) ORDER BY sold_at DESC,id) FROM page),'[]'::jsonb))::jsonb;
