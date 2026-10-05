CREATE OR REPLACE FUNCTION app.product_document(p app.products) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object(
 'id',p.id,'sku',p.sku,'name',p.name,'barcode',p.barcode,'category_id',p.category_id,'brand_id',p.brand_id,
 'category_name',(SELECT name FROM app.categories WHERE id=p.category_id),'brand_name',(SELECT name FROM app.brands WHERE id=p.brand_id),
 'country_code',p.country_code,'description',p.description,'base_unit_code',p.base_unit_code,
 'minimum_stock',p.minimum_stock::text,'tracks_expiry',p.tracks_expiry,'is_active',p.is_active,
 'archived_at',p.archived_at,'version',p.version::text,'created_at',p.created_at,'updated_at',p.updated_at,
 'packaging',COALESCE((SELECT jsonb_agg(jsonb_build_object('unit_code',u.unit_code,'units_per_pack',u.units_per_pack::text,'barcode',u.barcode,'retail_price_mmk',u.retail_price_mmk::text,'wholesale_price_mmk',u.wholesale_price_mmk::text,'is_default_purchase',u.is_default_purchase,'is_default_sale',u.is_default_sale) ORDER BY u.units_per_pack,u.unit_code) FROM app.product_units u WHERE u.product_id=p.id),'[]'::jsonb))
$$;
