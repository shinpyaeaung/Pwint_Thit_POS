-- name: ListProducts :one
WITH filtered AS (
 SELECT p.* FROM app.products p WHERE
 (CASE sqlc.arg(status)::text WHEN 'archived' THEN p.archived_at IS NOT NULL WHEN 'active' THEN p.archived_at IS NULL AND p.is_active WHEN 'inactive' THEN p.archived_at IS NULL AND NOT p.is_active ELSE p.archived_at IS NULL END)
 AND (sqlc.narg(category_id)::uuid IS NULL OR p.category_id=sqlc.narg(category_id))
 AND (sqlc.narg(brand_id)::uuid IS NULL OR p.brand_id=sqlc.narg(brand_id))
 AND (sqlc.arg(search)::text='' OR strpos(lower(p.name),lower(sqlc.arg(search)))>0 OR strpos(lower(p.sku),lower(sqlc.arg(search)))>0 OR strpos(COALESCE(p.barcode,''),sqlc.arg(search))>0 OR EXISTS(SELECT 1 FROM app.product_units pu WHERE pu.product_id=p.id AND strpos(COALESCE(pu.barcode,''),sqlc.arg(search))>0))
), page AS (SELECT * FROM filtered ORDER BY created_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'products',COALESCE((SELECT jsonb_agg(app.product_document(p) ORDER BY p.created_at DESC,p.id) FROM app.products p JOIN page f USING(id)),'[]'::jsonb))::jsonb;
-- name: GetProduct :one
SELECT app.product_document(p)::jsonb FROM app.products p WHERE p.id=$1;
-- name: LockProduct :one
SELECT id,base_unit_code,version,archived_at FROM app.products WHERE id=$1 FOR UPDATE;
-- name: ProductInUse :one
SELECT EXISTS(SELECT 1 FROM app.purchase_items x WHERE x.product_id=$1 UNION ALL SELECT 1 FROM app.sale_items x WHERE x.product_id=$1 UNION ALL SELECT 1 FROM app.batches x WHERE x.product_id=$1 UNION ALL SELECT 1 FROM app.damaged_products x WHERE x.product_id=$1 UNION ALL SELECT 1 FROM app.missing_products x WHERE x.product_id=$1)::boolean;
-- name: InsertProduct :one
INSERT INTO app.products(sku,name,barcode,category_id,brand_id,country_code,description,base_unit_code,minimum_stock,tracks_expiry,is_active)
SELECT d->>'sku',d->>'name',NULLIF(d->>'barcode',''),NULLIF(d->>'category_id','')::uuid,NULLIF(d->>'brand_id','')::uuid,NULLIF(d->>'country_code',''),NULLIF(d->>'description',''),d->>'base_unit_code',NULLIF(d->>'minimum_stock','')::numeric,(d->>'tracks_expiry')::boolean,(d->>'is_active')::boolean FROM (SELECT sqlc.arg(data)::jsonb d) t RETURNING id;
-- name: UpdateProduct :exec
UPDATE app.products SET sku=d->>'sku',name=d->>'name',barcode=NULLIF(d->>'barcode',''),category_id=NULLIF(d->>'category_id','')::uuid,brand_id=NULLIF(d->>'brand_id','')::uuid,country_code=NULLIF(d->>'country_code',''),description=NULLIF(d->>'description',''),base_unit_code=d->>'base_unit_code',minimum_stock=NULLIF(d->>'minimum_stock','')::numeric,tracks_expiry=(d->>'tracks_expiry')::boolean,is_active=(d->>'is_active')::boolean FROM (SELECT sqlc.arg(data)::jsonb d) t WHERE id=sqlc.arg(id);
-- name: ArchiveProduct :exec
UPDATE app.products SET is_active=false,archived_at=clock_timestamp() WHERE id=$1;
-- name: ResetProductDefaults :exec
UPDATE app.product_units SET is_default_purchase=false,is_default_sale=false WHERE product_id=$1;
-- name: RemoveProductUnits :exec
DELETE FROM app.product_units WHERE product_id=$1 AND NOT(unit_code=ANY(sqlc.arg(keep_codes)::text[]));
-- name: UpsertProductUnit :exec
INSERT INTO app.product_units(product_id,unit_code,units_per_pack,barcode,is_default_purchase,is_default_sale)
VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(product_id,unit_code) DO UPDATE SET units_per_pack=excluded.units_per_pack,barcode=excluded.barcode,is_default_purchase=excluded.is_default_purchase,is_default_sale=excluded.is_default_sale;
-- name: CatalogMetadata :one
SELECT jsonb_build_object('categories',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'is_active',is_active) ORDER BY lower(name),id) FROM app.categories),'[]'::jsonb),'brands',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'is_active',is_active) ORDER BY lower(name),id) FROM app.brands),'[]'::jsonb),'units',(SELECT jsonb_agg(jsonb_build_object('code',code,'name',name) ORDER BY name) FROM app.units))::jsonb;
-- name: ProductReferencesValid :one
SELECT (EXISTS(SELECT 1 FROM app.units WHERE code=sqlc.arg(base_unit)::text)
 AND (sqlc.narg(category_id)::uuid IS NULL OR EXISTS(SELECT 1 FROM app.categories WHERE id=sqlc.narg(category_id) AND is_active))
 AND (sqlc.narg(brand_id)::uuid IS NULL OR EXISTS(SELECT 1 FROM app.brands WHERE id=sqlc.narg(brand_id) AND is_active)))::boolean;
-- name: RecordProductAudit :exec
INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value) VALUES($1,$2,$3,$4,$5,$6);
