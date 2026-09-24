-- name: PurchaseCurrencies :one
SELECT COALESCE(jsonb_agg(jsonb_build_object('code',code,'name',name,'minor_units',minor_units) ORDER BY code),'[]'::jsonb)::jsonb FROM app.currencies WHERE is_active;
-- name: CreatePurchaseCurrency :exec
INSERT INTO app.currencies(code,name,minor_units) VALUES($1,$2,$3);
-- name: PurchaseRates :one
SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'currency_code',currency_code,'mmk_per_unit',mmk_per_unit::text,'effective_at',effective_at,'source',source) ORDER BY effective_at DESC,id),'[]'::jsonb)::jsonb FROM (SELECT * FROM app.exchange_rates WHERE currency_code=sqlc.arg(currency)::text AND effective_at<=sqlc.arg(as_of)::timestamptz ORDER BY effective_at DESC,id LIMIT 100) r;
-- name: CreatePurchaseRate :one
INSERT INTO app.exchange_rates(currency_code,mmk_per_unit,effective_at,source,recorded_by) VALUES($1,$2,$3,$4,$5) RETURNING id;
-- name: GetPurchaseRate :one
SELECT currency_code,mmk_per_unit::text AS rate,effective_at FROM app.exchange_rates WHERE id=$1;
-- name: PurchaseSupplierOptions :one
SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code) ORDER BY name,id),'[]'::jsonb)::jsonb FROM (SELECT id,name,code FROM app.suppliers WHERE is_active AND archived_at IS NULL AND (sqlc.arg(search)::text='' OR strpos(lower(name||' '||code),lower(sqlc.arg(search)))>0) ORDER BY name,id LIMIT 50) s;
-- name: PurchaseProductOptions :one
SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'sku',p.sku,'packaging',COALESCE((SELECT jsonb_agg(jsonb_build_object('unit_code',u.unit_code,'unit_name',un.name,'units_per_pack',u.units_per_pack::text,'is_default_purchase',u.is_default_purchase) ORDER BY u.units_per_pack) FROM app.product_units u JOIN app.units un ON un.code=u.unit_code WHERE u.product_id=p.id),'[]'::jsonb)) ORDER BY p.name,p.id),'[]'::jsonb)::jsonb FROM (SELECT id,name,sku FROM app.products WHERE is_active AND archived_at IS NULL AND (sqlc.arg(search)::text='' OR strpos(lower(name||' '||sku),lower(sqlc.arg(search)))>0) ORDER BY name,id LIMIT 50) p;
-- name: LockPurchaseSupplier :one
SELECT id FROM app.suppliers WHERE id=$1 AND is_active AND archived_at IS NULL FOR SHARE;
-- name: LockPurchaseCurrency :one
SELECT code FROM app.currencies WHERE code=$1 AND is_active FOR SHARE;
-- name: LockPurchasePackaging :one
SELECT p.name,p.sku,u.name AS unit_name,pu.units_per_pack::text AS units_per_pack FROM app.products p JOIN app.product_units pu ON pu.product_id=p.id JOIN app.units u ON u.code=pu.unit_code WHERE p.id=$1 AND pu.unit_code=$2 AND p.is_active AND p.archived_at IS NULL FOR SHARE OF p,pu,u;
-- name: LockPurchaseRequest :exec
SELECT pg_advisory_xact_lock(hashtextextended(sqlc.arg(request_key)::text,0));
-- name: FindPurchaseRequest :one
SELECT id,request_hash FROM app.purchases WHERE request_id=$1;
-- name: InsertPurchase :one
INSERT INTO app.purchases(purchase_number,supplier_id,supplier_invoice_number,purchased_at,due_date,currency_code,exchange_rate_id,mmk_per_unit,created_by,notes,request_id,request_hash)
SELECT d->>'purchase_number',(d->>'supplier_id')::uuid,NULLIF(d->>'supplier_invoice_number',''),(d->>'purchased_at')::timestamptz,NULLIF(d->>'due_date','')::date,d->>'currency_code',NULLIF(d->>'exchange_rate_id','')::uuid,(d->>'mmk_per_unit')::numeric,sqlc.arg(actor_id),NULLIF(d->>'notes',''),(d->>'request_id')::uuid,sqlc.arg(request_hash) FROM (SELECT sqlc.arg(data)::jsonb d) x RETURNING id;
-- name: InsertPurchaseItem :exec
INSERT INTO app.purchase_items(purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original,discount_original,tax_original,product_name_snapshot,sku_snapshot,unit_name_snapshot)
SELECT sqlc.arg(purchase_id),sqlc.arg(line_number),(d->>'product_id')::uuid,d->>'unit_code',(d->>'quantity')::numeric,(d->>'units_per_pack')::numeric,(d->>'unit_price_original')::numeric,(d->>'discount_original')::numeric,(d->>'tax_original')::numeric,sqlc.arg(product_name),sqlc.arg(sku),sqlc.arg(unit_name) FROM (SELECT sqlc.arg(data)::jsonb d) x;
-- name: PostPurchase :exec
UPDATE app.purchases SET status='POSTED',posted_at=clock_timestamp() WHERE id=$1 AND status='DRAFT';
-- name: GetPurchaseDocument :one
SELECT app.purchase_document(p,sqlc.arg(costs)::boolean,true)::jsonb FROM app.purchases p WHERE id=sqlc.arg(id);
-- name: ListPurchaseDocuments :one
WITH filtered AS (SELECT p.* FROM app.purchases p WHERE (sqlc.arg(search)::text='' OR strpos(lower(p.purchase_number||' '||COALESCE(p.supplier_invoice_number,'')),lower(sqlc.arg(search)))>0 OR EXISTS(SELECT 1 FROM app.suppliers s WHERE s.id=p.supplier_id AND strpos(lower(s.name),lower(sqlc.arg(search)))>0)) AND (sqlc.arg(currency)::text='' OR p.currency_code=sqlc.arg(currency)) AND (sqlc.arg(status)::text='' OR p.status=sqlc.arg(status))),
page AS (SELECT id FROM filtered ORDER BY purchased_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'purchases',COALESCE((SELECT jsonb_agg(app.purchase_document(p,sqlc.arg(costs)::boolean,false) ORDER BY p.purchased_at DESC,p.id) FROM app.purchases p JOIN page f USING(id)),'[]'::jsonb))::jsonb;
-- name: SupplierPurchaseBalance :one
SELECT jsonb_build_object('supplier_id',s.id,'total_outstanding_mmk',COALESCE((SELECT sum(outstanding_mmk)::text FROM app.supplier_payables WHERE supplier_id=s.id),'0'),'currencies',COALESCE((SELECT jsonb_agg(to_jsonb(b) ORDER BY currency_code) FROM (SELECT currency_code,sum(outstanding_original)::text AS outstanding_original,sum(outstanding_mmk)::text AS outstanding_mmk,sum(amount_paid_mmk)::text AS amount_paid_mmk,count(*) AS purchase_count FROM app.supplier_payables WHERE supplier_id=s.id GROUP BY currency_code) b),'[]'::jsonb))::jsonb FROM app.suppliers s WHERE s.id=$1;
