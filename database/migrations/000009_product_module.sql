ALTER TABLE app.products ADD COLUMN archived_at timestamptz;
ALTER TABLE app.products ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK(version>0);
ALTER TABLE app.products ADD CONSTRAINT product_sku_not_blank CHECK(btrim(sku)<>'' AND length(sku)<=100);
ALTER TABLE app.products ADD CONSTRAINT archived_product_inactive CHECK(archived_at IS NULL OR NOT is_active);
CREATE UNIQUE INDEX products_sku_ci ON app.products(lower(sku));
CREATE INDEX products_catalog_page ON app.products(created_at DESC,id) WHERE archived_at IS NULL;
CREATE INDEX products_category_status ON app.products(category_id,is_active) WHERE archived_at IS NULL;
CREATE INDEX products_brand_status ON app.products(brand_id,is_active) WHERE archived_at IS NULL;

-- One barcode namespace for base products and their packaging; the PK arbitrates concurrent writes.
CREATE TABLE app.catalog_barcodes (
 barcode text PRIMARY KEY CHECK(btrim(barcode)<>''),
 product_id uuid NOT NULL REFERENCES app.products(id),
 unit_code text REFERENCES app.units(code)
);
INSERT INTO app.catalog_barcodes SELECT barcode,id,NULL FROM app.products WHERE barcode IS NOT NULL;
INSERT INTO app.catalog_barcodes SELECT barcode,product_id,unit_code FROM app.product_units WHERE barcode IS NOT NULL;
CREATE INDEX catalog_barcodes_product ON app.catalog_barcodes(product_id);
CREATE FUNCTION app.sync_catalog_barcode() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pid uuid; unit text;
BEGIN
 IF TG_OP <> 'INSERT' AND OLD.barcode IS NOT NULL THEN DELETE FROM app.catalog_barcodes WHERE barcode=OLD.barcode; END IF;
 IF TG_OP <> 'DELETE' AND NEW.barcode IS NOT NULL THEN
  IF TG_TABLE_NAME='products' THEN pid=NEW.id; unit=NULL; ELSE pid=NEW.product_id; unit=NEW.unit_code; END IF;
  INSERT INTO app.catalog_barcodes(barcode,product_id,unit_code) VALUES(NEW.barcode,pid,unit);
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER products_barcode AFTER INSERT OR UPDATE OF barcode OR DELETE ON app.products FOR EACH ROW EXECUTE FUNCTION app.sync_catalog_barcode();
CREATE TRIGGER units_barcode AFTER INSERT OR UPDATE OF barcode OR DELETE ON app.product_units FOR EACH ROW EXECUTE FUNCTION app.sync_catalog_barcode();
CREATE FUNCTION app.bump_product_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.version=OLD.version+1; RETURN NEW; END $$;
CREATE TRIGGER product_version BEFORE UPDATE ON app.products FOR EACH ROW EXECUTE FUNCTION app.bump_product_version();

INSERT INTO app.permissions(code,description,is_sensitive) VALUES ('products.delete','Archive products while preserving history',true),('catalog.manage','Manage categories, brands and unit definitions',false);
INSERT INTO app.user_permissions(user_id,permission_code,granted_by)
SELECT u.user_id,p.code,u.granted_by FROM app.user_permissions u CROSS JOIN (VALUES('products.delete'),('catalog.manage')) p(code) WHERE u.permission_code='products.manage';

CREATE FUNCTION app.product_document(p app.products) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object(
 'id',p.id,'sku',p.sku,'name',p.name,'barcode',p.barcode,'category_id',p.category_id,'brand_id',p.brand_id,
 'category_name',(SELECT name FROM app.categories WHERE id=p.category_id),'brand_name',(SELECT name FROM app.brands WHERE id=p.brand_id),
 'country_code',p.country_code,'description',p.description,'base_unit_code',p.base_unit_code,
 'minimum_stock',p.minimum_stock::text,'tracks_expiry',p.tracks_expiry,'is_active',p.is_active,
 'archived_at',p.archived_at,'version',p.version::text,'created_at',p.created_at,'updated_at',p.updated_at,
 'packaging',COALESCE((SELECT jsonb_agg(jsonb_build_object('unit_code',u.unit_code,'units_per_pack',u.units_per_pack::text,'barcode',u.barcode,'is_default_purchase',u.is_default_purchase,'is_default_sale',u.is_default_sale) ORDER BY u.units_per_pack,u.unit_code) FROM app.product_units u WHERE u.product_id=p.id),'[]'::jsonb))
$$;
