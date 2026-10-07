-- Existing transport amounts remain total fees; do not rewrite historical rows.
ALTER TABLE app.transportation_stages ADD COLUMN fee_basis text NOT NULL DEFAULT 'TOTAL' CHECK(fee_basis IN('TOTAL','PER_CARTON'));
ALTER TABLE app.transportation_stages ADD COLUMN fee_per_carton_mmk numeric(20,4);
ALTER TABLE app.transportation_stages ADD COLUMN charged_cartons numeric(20,6);
ALTER TABLE app.transportation_stages ADD CONSTRAINT transport_fee_basis_valid CHECK(
 (fee_basis='TOTAL' AND fee_per_carton_mmk IS NULL AND charged_cartons IS NULL) OR
 (fee_basis='PER_CARTON' AND fee_per_carton_mmk IS NOT NULL AND fee_per_carton_mmk>=0 AND fee_per_carton_mmk<>'NaN'
 AND charged_cartons IS NOT NULL AND charged_cartons>0 AND charged_cartons<>'NaN'
 AND transportation_fee_mmk=round(fee_per_carton_mmk*charged_cartons,4)));
CREATE FUNCTION app.calculate_transport_fee() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.fee_basis='PER_CARTON' THEN
  NEW.transportation_fee_mmk=round(NEW.fee_per_carton_mmk*NEW.charged_cartons,4);
 ELSE
  NEW.fee_per_carton_mmk=NULL; NEW.charged_cartons=NULL;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER calculate_transport_fee BEFORE INSERT OR UPDATE ON app.transportation_stages FOR EACH ROW EXECUTE FUNCTION app.calculate_transport_fee();

-- Prefer the historical purchase carton conversion. Other purchase units use
-- the configured carton conversion only as an editable billing suggestion.
CREATE FUNCTION app.shipment_cartons(shipment uuid) RETURNS numeric LANGUAGE sql STABLE AS $$
 SELECT CASE WHEN count(*)>0 AND count(pack)=count(*) THEN round(sum(expected_quantity/pack),6) END
 FROM (SELECT si.expected_quantity,CASE WHEN pi.unit_code='CARTON' THEN pi.units_per_pack ELSE u.units_per_pack END AS pack
 FROM app.shipment_items si JOIN app.purchase_items pi ON pi.id=si.purchase_item_id
 LEFT JOIN app.product_units u ON u.product_id=si.product_id AND u.unit_code='CARTON'
 WHERE si.shipment_id=shipment) items
$$;
DO $$ DECLARE definition text; needle text;
BEGIN
 definition=pg_get_functiondef('app.stage_document(app.transportation_stages,boolean)'::regprocedure);
 needle='''transportation_fee_mmk'',t.transportation_fee_mmk::text';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected stage document'; END IF;
 definition=replace(definition,needle,'''fee_basis'',t.fee_basis,''fee_per_carton_mmk'',t.fee_per_carton_mmk::text,''charged_cartons'',t.charged_cartons::text,'||needle);
 EXECUTE definition;
 definition=pg_get_functiondef('app.shipment_document(app.shipments,boolean)'::regprocedure);
 needle='''shipment_number'',s.shipment_number';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected shipment document'; END IF;
 definition=replace(definition,needle,'''suggested_cartons'',app.shipment_cartons(s.id)::text,'||needle);
 EXECUTE definition;
END $$;
