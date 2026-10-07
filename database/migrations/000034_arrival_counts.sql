-- Legacy finalized costing remains unchanged. New confirmations retain the actual arrival counts.
ALTER TABLE app.shipment_items ADD COLUMN arrival_received_quantity numeric(20,6);
ALTER TABLE app.shipment_items ADD COLUMN arrival_damaged_quantity numeric(20,6);
ALTER TABLE app.shipment_items ADD CONSTRAINT arrival_counts_valid CHECK(
 (arrival_received_quantity IS NULL AND arrival_damaged_quantity IS NULL) OR
 (arrival_received_quantity IS NOT NULL AND arrival_damaged_quantity IS NOT NULL
 AND arrival_received_quantity>=0 AND arrival_received_quantity<=expected_quantity AND arrival_received_quantity<>'NaN'
 AND arrival_damaged_quantity>=0 AND arrival_damaged_quantity<=arrival_received_quantity AND arrival_damaged_quantity<>'NaN'
 AND costing_sellable_quantity IS NOT NULL AND costing_sellable_quantity=arrival_received_quantity-arrival_damaged_quantity));
CREATE FUNCTION app.check_arrival_counts() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.arrival_received_quantity IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.shipments WHERE id=NEW.shipment_id AND status='ARRIVED') THEN
  RAISE EXCEPTION 'shipment: Confirm received and damaged quantities only after arrival.' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER check_arrival_counts BEFORE INSERT OR UPDATE ON app.shipment_items FOR EACH ROW EXECUTE FUNCTION app.check_arrival_counts();
DO $$ DECLARE definition text; needle text;
BEGIN
 definition=pg_get_functiondef('app.post_receiving(jsonb,uuid)'::regprocedure);
 needle='received=cartons*coalesce(pack,0)+loose; sellable=received-damaged;';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected receiving definition'; END IF;
 definition=replace(definition,needle,needle||$patch$
  IF si.arrival_received_quantity IS NOT NULL AND (received<>si.arrival_received_quantity OR damaged<>si.arrival_damaged_quantity) THEN RAISE EXCEPTION 'receiving: Receipt counts must match the received and damaged quantities confirmed after arrival.' USING ERRCODE='23514'; END IF;
$patch$);
 EXECUTE definition;
END $$;
