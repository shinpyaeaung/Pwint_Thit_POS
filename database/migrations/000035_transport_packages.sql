-- Add package billing without rewriting historical transportation amounts.
ALTER TABLE app.transportation_stages DROP CONSTRAINT transportation_stages_fee_basis_check;
ALTER TABLE app.transportation_stages ADD CONSTRAINT transportation_stages_fee_basis_check CHECK(fee_basis IN('TOTAL','PER_CARTON','PER_PACKAGE'));
ALTER TABLE app.transportation_stages ADD COLUMN package_type text REFERENCES app.units(code);
ALTER TABLE app.transportation_stages ADD COLUMN package_quantity numeric(20,6);
ALTER TABLE app.transportation_stages ADD COLUMN fee_per_package_mmk numeric(20,4);
ALTER TABLE app.transportation_stages DROP CONSTRAINT transport_fee_basis_valid;
ALTER TABLE app.transportation_stages ADD CONSTRAINT transport_fee_basis_valid CHECK(
 (fee_basis='TOTAL' AND fee_per_carton_mmk IS NULL AND charged_cartons IS NULL AND package_type IS NULL AND package_quantity IS NULL AND fee_per_package_mmk IS NULL) OR
 (fee_basis='PER_CARTON' AND fee_per_carton_mmk IS NOT NULL AND fee_per_carton_mmk>=0 AND fee_per_carton_mmk<>'NaN' AND charged_cartons IS NOT NULL AND charged_cartons>0 AND charged_cartons<>'NaN' AND transportation_fee_mmk=round(fee_per_carton_mmk*charged_cartons,4) AND package_type IS NULL AND package_quantity IS NULL AND fee_per_package_mmk IS NULL) OR
 (fee_basis='PER_PACKAGE' AND package_type IS NOT NULL AND package_quantity IS NOT NULL AND package_quantity>0 AND package_quantity<>'NaN' AND fee_per_package_mmk IS NOT NULL AND fee_per_package_mmk>=0 AND fee_per_package_mmk<>'NaN' AND transportation_fee_mmk=round(fee_per_package_mmk*package_quantity,4) AND fee_per_carton_mmk IS NULL AND charged_cartons IS NULL));
CREATE OR REPLACE FUNCTION app.calculate_transport_fee() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.fee_basis='PER_PACKAGE' THEN
  NEW.transportation_fee_mmk=round(NEW.fee_per_package_mmk*NEW.package_quantity,4);
  NEW.fee_per_carton_mmk=NULL; NEW.charged_cartons=NULL;
 ELSE
  NEW.package_type=NULL; NEW.package_quantity=NULL; NEW.fee_per_package_mmk=NULL;
  IF NEW.fee_basis='PER_CARTON' THEN
   NEW.transportation_fee_mmk=round(NEW.fee_per_carton_mmk*NEW.charged_cartons,4);
  ELSE
   NEW.fee_per_carton_mmk=NULL; NEW.charged_cartons=NULL;
  END IF;
 END IF;
 RETURN NEW;
END $$;

-- Historical purchase conversions take precedence over current catalog conversions.
-- A suggestion is only given when every shipment line has this packaging type.
CREATE FUNCTION app.shipment_package_options(shipment uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
 WITH lines AS (SELECT si.id,si.product_id,si.expected_quantity,pi.unit_code,pi.units_per_pack FROM app.shipment_items si JOIN app.purchase_items pi ON pi.id=si.purchase_item_id WHERE si.shipment_id=shipment),
 conversions AS (
  SELECT l.id,l.expected_quantity,l.unit_code,l.units_per_pack FROM lines l
  UNION ALL
  SELECT l.id,l.expected_quantity,u.unit_code,u.units_per_pack FROM lines l JOIN app.product_units u ON u.product_id=l.product_id AND u.unit_code<>l.unit_code
 ), options AS (
 SELECT c.unit_code,u.name, max(c.units_per_pack) AS size,
 CASE WHEN count(*)=(SELECT count(*) FROM lines) THEN round(sum(c.expected_quantity/c.units_per_pack),6)::text END AS quantity
 FROM conversions c JOIN app.units u ON u.code=c.unit_code GROUP BY c.unit_code,u.name)
 SELECT coalesce(jsonb_agg(jsonb_build_object('code',unit_code,'name',name,'quantity',quantity) ORDER BY (quantity IS NOT NULL) DESC,size DESC,unit_code),'[]'::jsonb) FROM options
$$;
DO $$ DECLARE definition text; needle text;
BEGIN
 definition=pg_get_functiondef('app.stage_document(app.transportation_stages,boolean)'::regprocedure);
 needle='''transportation_fee_mmk'',t.transportation_fee_mmk::text';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected stage document'; END IF;
 definition=replace(definition,needle,'''package_type'',CASE WHEN t.fee_basis=''PER_CARTON'' THEN ''CARTON'' ELSE t.package_type END,''package_quantity'',coalesce(t.package_quantity,t.charged_cartons)::text,''fee_per_package_mmk'',coalesce(t.fee_per_package_mmk,t.fee_per_carton_mmk)::text,'||needle);
 EXECUTE definition;
 definition=pg_get_functiondef('app.shipment_document(app.shipments,boolean)'::regprocedure);
 needle='''shipment_number'',s.shipment_number';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected shipment document'; END IF;
 definition=replace(definition,needle,'''package_options'',app.shipment_package_options(s.id),'||needle);
 EXECUTE definition;
END $$;
