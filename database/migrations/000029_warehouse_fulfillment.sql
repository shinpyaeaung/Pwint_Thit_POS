-- Warehouse prices are independent per product/unit; defaults remain compatible.
CREATE TABLE app.warehouse_prices (
 warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 product_id uuid NOT NULL, unit_code text NOT NULL,
 retail_price_mmk numeric(20,4) NOT NULL CHECK(retail_price_mmk>=0 AND retail_price_mmk<>'NaN'),
 wholesale_price_mmk numeric(20,4) NOT NULL CHECK(wholesale_price_mmk>=0 AND wholesale_price_mmk<>'NaN'),
 PRIMARY KEY(warehouse_id,product_id,unit_code),
 FOREIGN KEY(product_id,unit_code) REFERENCES app.product_units(product_id,unit_code) ON DELETE CASCADE
);
CREATE FUNCTION app.warehouse_prices_save(d jsonb,actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p app.products; before jsonb;
BEGIN
 SELECT * INTO p FROM app.products WHERE id=(d->>'product_id')::uuid AND is_active AND archived_at IS NULL FOR UPDATE;
 IF NOT FOUND OR p.version::text<>d->>'version' THEN RAISE EXCEPTION 'pos: Product changed. Refresh prices.' USING ERRCODE='23514'; END IF;
 PERFORM id FROM app.warehouses WHERE id=(d->>'warehouse_id')::uuid AND is_active FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'pos: Choose an active warehouse.' USING ERRCODE='23514'; END IF;
 SELECT to_jsonb(wp) INTO before FROM app.warehouse_prices wp WHERE wp.warehouse_id=(d->>'warehouse_id')::uuid AND wp.product_id=p.id AND wp.unit_code=d->>'unit_code';
 INSERT INTO app.warehouse_prices VALUES((d->>'warehouse_id')::uuid,p.id,d->>'unit_code',(d->>'retail_price_mmk')::numeric,(d->>'wholesale_price_mmk')::numeric)
 ON CONFLICT(warehouse_id,product_id,unit_code) DO UPDATE SET retail_price_mmk=excluded.retail_price_mmk,wholesale_price_mmk=excluded.wholesale_price_mmk;
 UPDATE app.products SET version=version+1 WHERE id=p.id;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value) VALUES(actor,'warehouse_prices.save','products',p.id,before,d);
END $$;

-- Existing shipments keep an unknown method instead of inventing historical delivery details.
ALTER TABLE app.shipments ADD COLUMN fulfillment jsonb;
CREATE FUNCTION app.valid_fulfillment(d jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT jsonb_typeof(d)='object' AND coalesce(d->>'mode','') IN ('DELIVERY','COLLECTION')
 AND length(coalesce(d->>'person_name',''))<=200 AND length(coalesce(d->>'vehicle_number',''))<=100
$$;
ALTER TABLE app.shipments ADD CONSTRAINT shipment_fulfillment_valid CHECK(fulfillment IS NULL OR app.valid_fulfillment(fulfillment));

-- Preserve the current checkout, approvals, numbering and FIFO reservation logic.
DO $$ DECLARE definition text; needle text;
BEGIN
 definition=pg_get_functiondef('app.pos_sale(jsonb,uuid,boolean,boolean,boolean)'::regprocedure);
 needle='price=CASE d->>''pricing_mode'' WHEN ''RETAIL'' THEN pack.retail_price_mmk WHEN ''WHOLESALE'' THEN pack.wholesale_price_mmk END;';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected checkout pricing definition'; END IF;
 definition=replace(definition,needle,needle||$patch$
  price=coalesce((SELECT CASE d->>'pricing_mode' WHEN 'RETAIL' THEN wp.retail_price_mmk ELSE wp.wholesale_price_mmk END FROM app.warehouse_prices wp WHERE wp.warehouse_id=warehouse AND wp.product_id=product.id AND wp.unit_code=pack.unit_code),price);
$patch$);
 needle='doc=jsonb_build_object(''business_date''';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected invoice definition'; END IF;
 definition=replace(definition,needle,$patch$
 IF d ? 'fulfillment' AND NOT app.valid_fulfillment(d->'fulfillment') THEN RAISE EXCEPTION 'pos: Invalid collection or delivery details.' USING ERRCODE='23514'; END IF;
 doc=jsonb_build_object('fulfillment',coalesce(d->'fulfillment','{"mode":"COLLECTION"}'::jsonb)) || jsonb_build_object('business_date'$patch$);
 EXECUTE definition;
 definition=pg_get_functiondef('app.shipment_document(app.shipments,boolean)'::regprocedure);
 definition=replace(definition,'''start_location'',s.start_location','''fulfillment'',s.fulfillment,''start_location'',s.start_location');
 EXECUTE definition;
 -- Convert the requested pack quantity on the server, after the retry check.
 definition=pg_get_functiondef('app.stock_issue(jsonb,uuid)'::regprocedure);
 needle='PERFORM id FROM app.products WHERE id=b.product_id FOR UPDATE;';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected stock issue definition'; END IF;
 definition=replace(definition,needle,needle||$patch$
 IF coalesce(d->>'unit_code','')<>'' THEN
  IF NOT EXISTS(SELECT 1 FROM app.product_units WHERE product_id=b.product_id AND unit_code=d->>'unit_code' AND units_per_pack=(d->>'units_per_pack')::numeric) THEN
   RAISE EXCEPTION 'pos: Packaging changed. Refresh stock.' USING ERRCODE='23514';
  END IF;
  qty=qty*(d->>'units_per_pack')::numeric;
  IF qty<>round(qty,6) THEN RAISE EXCEPTION 'pos: Quantity exceeds stock precision.' USING ERRCODE='23514'; END IF;
 END IF;
$patch$);
 EXECUTE definition;
END $$;
