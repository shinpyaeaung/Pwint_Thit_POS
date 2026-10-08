-- Each warehouse leg owns a normal shipment for its cargo stages and payments.
ALTER TABLE app.stock_transfers ADD COLUMN shipment_id uuid UNIQUE REFERENCES app.shipments(id);
ALTER TABLE app.stock_transfers ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.stock_transfers ADD COLUMN request_payload jsonb;
ALTER TABLE app.stock_transfers ADD COLUMN receipt_payload jsonb;
ALTER TABLE app.stock_transfers ADD COLUMN cost_document jsonb;
CREATE TRIGGER business_number BEFORE INSERT ON app.stock_transfers FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('transfer_number','TRF');
ALTER TABLE app.stock_transfer_items ADD COLUMN source_unit_cost_mmk numeric(24,8);
ALTER TABLE app.stock_transfer_items ADD COLUMN damaged_quantity numeric(20,6);
ALTER TABLE app.stock_transfer_items ADD COLUMN notes text;
ALTER TABLE app.stock_transfer_items ADD CHECK(damaged_quantity IS NULL OR (damaged_quantity>=0 AND damaged_quantity<=received_quantity AND damaged_quantity<>'NaN'));
ALTER TABLE app.batches ALTER COLUMN receiving_item_id DROP NOT NULL;
ALTER TABLE app.batches ADD COLUMN transfer_item_id uuid UNIQUE REFERENCES app.stock_transfer_items(id);
ALTER TABLE app.batches ADD COLUMN source_batch_id uuid REFERENCES app.batches(id);
ALTER TABLE app.batches ADD COLUMN carton_size numeric(20,6);
ALTER TABLE app.batches ADD CHECK(num_nonnulls(receiving_item_id,transfer_item_id)=1 AND ((transfer_item_id IS NULL)=(source_batch_id IS NULL)));

CREATE FUNCTION app.dispatch_transfer(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE prior app.stock_transfers; result uuid; shipment uuid; x jsonb; stock app.inventory; batch app.batches; item uuid; qty numeric; origin text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO prior FROM app.stock_transfers WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
  IF prior.created_by<>actor OR prior.request_payload<>d THEN RAISE EXCEPTION 'receiving: Request already used with different contents.' USING ERRCODE='23514'; END IF;
  RETURN prior.shipment_id;
 END IF;
 IF (d->>'from_warehouse_id')::uuid=(d->>'to_warehouse_id')::uuid THEN RAISE EXCEPTION 'receiving: Choose different source and destination warehouses.' USING ERRCODE='23514'; END IF;
 PERFORM id FROM app.warehouses WHERE id IN((d->>'from_warehouse_id')::uuid,(d->>'to_warehouse_id')::uuid) AND is_active ORDER BY id FOR SHARE;
 IF (SELECT count(*) FROM app.warehouses WHERE id IN((d->>'from_warehouse_id')::uuid,(d->>'to_warehouse_id')::uuid) AND is_active)<>2 THEN RAISE EXCEPTION 'receiving: Choose two active warehouses.' USING ERRCODE='23514'; END IF;
 IF jsonb_array_length(d->'items') NOT BETWEEN 1 AND 100 OR (SELECT count(DISTINCT value->>'batch_id') FROM jsonb_array_elements(d->'items'))<>jsonb_array_length(d->'items') THEN RAISE EXCEPTION 'receiving: Include 1–100 distinct source batches.' USING ERRCODE='23514'; END IF;
 SELECT name INTO origin FROM app.warehouses WHERE id=(d->>'from_warehouse_id')::uuid;
 INSERT INTO app.shipments(start_location,destination_warehouse_id,created_by,status,shipped_at,notes,fulfillment)
 VALUES(origin,(d->>'to_warehouse_id')::uuid,actor,'IN_TRANSIT',now(),nullif(d->>'notes',''),coalesce(d->'fulfillment','{"mode":"DELIVERY"}'::jsonb)) RETURNING id INTO shipment;
 INSERT INTO app.stock_transfers(from_warehouse_id,to_warehouse_id,status,dispatched_at,created_by,notes,shipment_id,request_id,request_payload)
 VALUES((d->>'from_warehouse_id')::uuid,(d->>'to_warehouse_id')::uuid,'IN_TRANSIT',now(),actor,d->>'notes',shipment,(d->>'request_id')::uuid,d) RETURNING id INTO result;
 FOR x IN SELECT value FROM jsonb_array_elements(d->'items') ORDER BY value->>'batch_id' LOOP
  SELECT * INTO stock FROM app.inventory WHERE warehouse_id=(d->>'from_warehouse_id')::uuid AND batch_id=(x->>'batch_id')::uuid FOR UPDATE;
  IF NOT FOUND OR stock.version::text<>x->>'version' THEN RAISE EXCEPTION 'receiving: Source stock changed. Reload before dispatch.' USING ERRCODE='23514'; END IF;
  SELECT * INTO batch FROM app.batches WHERE id=stock.batch_id;
  qty=(x->>'quantity')::numeric;
  IF qty IS NULL OR qty<=0 OR qty='NaN' OR qty<>round(qty,6) OR qty>stock.available_quantity OR batch.finalized_at IS NULL OR batch.actual_unit_cost_mmk IS NULL THEN RAISE EXCEPTION 'receiving: Transfer quantity exceeds available costed stock.' USING ERRCODE='23514'; END IF;
  INSERT INTO app.stock_transfer_items(transfer_id,batch_id,quantity,source_unit_cost_mmk) VALUES(result,batch.id,qty,batch.actual_unit_cost_mmk) RETURNING id INTO item;
  INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,stock_transfer_item_id,idempotency_key,occurred_at,recorded_by,reason)
  VALUES(stock.warehouse_id,batch.id,'TRANSFER',-qty,batch.actual_unit_cost_mmk,item,'transfer-dispatch:'||item,clock_timestamp(),actor,'Dispatch '||result);
 END LOOP;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'transfers.dispatch','stock_transfers',result,d);
 RETURN shipment;
END $$;

CREATE FUNCTION app.receive_transfer(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE tr app.stock_transfers; sh app.shipments; item app.stock_transfer_items; source app.batches; x jsonb; result uuid;
 received numeric; damaged numeric; qty_total numeric; qty_before numeric=0; cargo numeric; extra numeric; allocated_cargo numeric; allocated_extra numeric; carried numeric; purchase numeric; transport numeric; other numeric; pack numeric; lines jsonb='[]'; when_at timestamptz=clock_timestamp();
BEGIN
 SELECT * INTO sh FROM app.shipments WHERE id=(d->>'shipment_id')::uuid FOR UPDATE;
 SELECT * INTO tr FROM app.stock_transfers WHERE shipment_id=sh.id FOR UPDATE;
 IF tr.id IS NULL THEN RAISE EXCEPTION 'receiving: Warehouse shipment not found.' USING ERRCODE='23514'; END IF;
 IF tr.status='RECEIVED' AND tr.receipt_payload=d THEN RETURN sh.id; END IF;
 IF tr.status<>'IN_TRANSIT' OR sh.version::text<>d->>'version' OR sh.costs_finalized_at IS NOT NULL THEN RAISE EXCEPTION 'receiving: Shipment changed or is already closed. Reload before receiving.' USING ERRCODE='23514'; END IF;
 IF jsonb_array_length(d->'items')<>(SELECT count(*) FROM app.stock_transfer_items WHERE transfer_id=tr.id) OR (SELECT count(DISTINCT value->>'id') FROM jsonb_array_elements(d->'items'))<>jsonb_array_length(d->'items') THEN RAISE EXCEPTION 'receiving: Reconcile every transferred batch exactly once.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(d->'items') entry WHERE NOT EXISTS(SELECT 1 FROM app.stock_transfer_items i WHERE i.id=(entry->>'id')::uuid AND i.transfer_id=tr.id)) THEN RAISE EXCEPTION 'receiving: Unknown transfer item.' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(total_mmk),0) INTO cargo FROM app.transportation_stages WHERE shipment_id=sh.id;
 SELECT coalesce(sum(amount_mmk),0) INTO extra FROM app.shipment_expenses WHERE shipment_id=sh.id AND voided_at IS NULL;
 SELECT sum(quantity) INTO qty_total FROM app.stock_transfer_items WHERE transfer_id=tr.id;
 FOR item IN SELECT * FROM app.stock_transfer_items WHERE transfer_id=tr.id ORDER BY id LOOP
  SELECT value INTO x FROM jsonb_array_elements(d->'items') WHERE (value->>'id')::uuid=item.id;
  received=(x->>'received_quantity')::numeric; damaged=(x->>'damaged_quantity')::numeric;
  IF received IS NULL OR damaged IS NULL OR received<0 OR received>item.quantity OR damaged<0 OR damaged>received OR received='NaN' OR damaged='NaN' OR received<>round(received,6) OR damaged<>round(damaged,6) THEN RAISE EXCEPTION 'receiving: Enter valid received and damaged quantities.' USING ERRCODE='23514'; END IF;
  IF (received<>item.quantity OR damaged>0) AND btrim(coalesce(x->>'notes',''))='' THEN RAISE EXCEPTION 'receiving: Explain missing or damaged stock.' USING ERRCODE='23514'; END IF;
  SELECT * INTO source FROM app.batches WHERE id=item.batch_id;
  allocated_cargo=round(cargo*(qty_before+item.quantity)/qty_total,4)-round(cargo*qty_before/qty_total,4);
  allocated_extra=round(extra*(qty_before+item.quantity)/qty_total,4)-round(extra*qty_before/qty_total,4);
  qty_before=qty_before+item.quantity;
  carried=round(item.source_unit_cost_mmk*item.quantity,4);
  purchase=least(carried,round(source.purchase_cost_mmk/source.sellable_quantity*item.quantity,4));
  transport=least(carried-purchase,round(source.transport_cost_mmk/source.sellable_quantity*item.quantity,4));
  other=carried-purchase-transport;
  SELECT coalesce(source.carton_size,r.carton_size) INTO pack FROM (SELECT 1) seed LEFT JOIN app.goods_receiving_items r ON r.id=source.receiving_item_id;
  UPDATE app.stock_transfer_items SET received_quantity=received,damaged_quantity=damaged,notes=x->>'notes' WHERE id=item.id;
  INSERT INTO app.batches(product_id,transfer_item_id,source_batch_id,batch_number,received_at,manufactured_on,expires_on,purchase_cost_mmk,transport_cost_mmk,other_cost_mmk,sellable_quantity,finalized_at,carton_size)
  VALUES(source.product_id,item.id,source.id,source.batch_number||' / '||tr.transfer_number,when_at,source.manufactured_on,source.expires_on,purchase,transport+allocated_cargo,other+allocated_extra,received-damaged,when_at,pack) RETURNING id INTO result;
  IF received>0 THEN
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,stock_transfer_item_id,idempotency_key,occurred_at,recorded_by,reason)
   SELECT tr.to_warehouse_id,b.id,'TRANSFER',received-damaged,damaged,b.actual_unit_cost_mmk,item.id,'transfer-receive:'||item.id,when_at,actor,coalesce(nullif(x->>'notes',''),'Receive '||tr.transfer_number) FROM app.batches b WHERE b.id=result;
  END IF;
  lines=lines||jsonb_build_array(jsonb_build_object('id',item.id,'batch_id',result,'source_batch_id',source.id,'received_quantity',received::text,'damaged_quantity',damaged::text,'missing_quantity',(item.quantity-received)::text,'carried_cost_mmk',carried::text,'cargo_cost_mmk',allocated_cargo::text,'additional_cost_mmk',allocated_extra::text,'landed_cost_mmk',(carried+allocated_cargo+allocated_extra)::text,'sellable_quantity',(received-damaged)::text));
 END LOOP;
 UPDATE app.stock_transfers SET status='RECEIVED',received_at=when_at,receipt_payload=d,cost_document=jsonb_build_object('items',lines,'cargo_mmk',cargo::text,'additional_mmk',extra::text,'allocation_method','QUANTITY') WHERE id=tr.id;
 UPDATE app.shipments SET status='RECEIVED',arrived_at=when_at,costs_finalized_at=when_at,costs_finalized_by=actor,allocation_method='QUANTITY',version=version+1 WHERE id=sh.id;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'transfers.receive','stock_transfers',tr.id,jsonb_build_object('input',d,'costing',lines));
 RETURN sh.id;
END $$;

CREATE FUNCTION app.cancel_transfer(d jsonb,actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE sh app.shipments; tr app.stock_transfers; movement app.inventory_movements;
BEGIN
 SELECT * INTO sh FROM app.shipments WHERE id=(d->>'shipment_id')::uuid FOR UPDATE;
 SELECT * INTO tr FROM app.stock_transfers WHERE shipment_id=sh.id FOR UPDATE;
 IF tr.id IS NULL OR tr.status<>'IN_TRANSIT' OR sh.version::text<>d->>'version' THEN RAISE EXCEPTION 'receiving: Shipment changed or is already closed.' USING ERRCODE='23514'; END IF;
 IF btrim(coalesce(d->>'reason',''))='' THEN RAISE EXCEPTION 'receiving: Explain why all dispatched goods returned to the source.' USING ERRCODE='23514'; END IF;
 -- Restore only after the operator confirms physical return; preserve cargo debts.
 FOR movement IN SELECT m.* FROM app.inventory_movements m JOIN app.stock_transfer_items i ON i.id=m.stock_transfer_item_id WHERE i.transfer_id=tr.id AND m.idempotency_key='transfer-dispatch:'||i.id ORDER BY m.batch_id LOOP
  INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,reverses_movement_id,idempotency_key,occurred_at,recorded_by,reason)
  VALUES(movement.warehouse_id,movement.batch_id,'REVERSAL',-movement.sellable_delta,movement.unit_cost_mmk,movement.id,'transfer-cancel:'||movement.id,clock_timestamp(),actor,d->>'reason');
 END LOOP;
 UPDATE app.stock_transfers SET status='CANCELLED' WHERE id=tr.id;
 UPDATE app.shipments SET status='CANCELLED',version=version+1 WHERE id=sh.id;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value,reason) VALUES(actor,'transfers.cancel','stock_transfers',tr.id,d,d->>'reason');
END $$;
-- Terminal transfer documents and their item snapshots are immutable.
CREATE TRIGGER protect_transfer_items BEFORE INSERT OR UPDATE OR DELETE ON app.stock_transfer_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('stock_transfers','transfer_id','received_at');
CREATE FUNCTION app.protect_transfer() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF OLD.status IN('RECEIVED','CANCELLED','REVERSED') THEN RAISE EXCEPTION 'closed transfer is immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_transfer BEFORE UPDATE OR DELETE ON app.stock_transfers FOR EACH ROW EXECUTE FUNCTION app.protect_transfer();
DO $$ DECLARE definition text; needle text;
BEGIN
 definition=pg_get_functiondef('app.shipment_document(app.shipments,boolean)'::regprocedure);
 needle='''shipment_number'',s.shipment_number';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected shipment document'; END IF;
 definition=replace(definition,needle,'''transfer_id'',(SELECT id FROM app.stock_transfers WHERE shipment_id=s.id),'||needle); EXECUTE definition;
END $$;
ALTER FUNCTION app.shipment_package_options(uuid) RENAME TO purchase_shipment_package_options;
CREATE OR REPLACE FUNCTION app.shipment_package_options(shipment uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
 WITH items AS (SELECT i.id,i.quantity,b.product_id FROM app.stock_transfer_items i JOIN app.stock_transfers t ON t.id=i.transfer_id JOIN app.batches b ON b.id=i.batch_id WHERE t.shipment_id=shipment), packs AS (
 SELECT p.unit_code,u.name,max(p.units_per_pack) AS size,CASE WHEN count(*)=(SELECT count(*) FROM items) THEN round(sum(i.quantity/p.units_per_pack),6)::text END AS quantity FROM items i JOIN app.product_units p ON p.product_id=i.product_id JOIN app.units u ON u.code=p.unit_code GROUP BY p.unit_code,u.name)
 SELECT CASE WHEN EXISTS(SELECT 1 FROM items) THEN coalesce((SELECT jsonb_agg(jsonb_build_object('code',unit_code,'name',name,'quantity',quantity) ORDER BY (quantity IS NOT NULL) DESC,size DESC,unit_code) FROM packs),'[]') ELSE app.purchase_shipment_package_options(shipment) END
$$;
-- Rebind the SQL document function after renaming its referenced helper.
DO $$ DECLARE definition text; BEGIN
 definition=pg_get_functiondef('app.shipment_document(app.shipments,boolean)'::regprocedure);
 definition=replace(definition,'app.purchase_shipment_package_options','app.shipment_package_options'); EXECUTE definition;
END $$;
CREATE OR REPLACE VIEW app.warehouse_pricing_costs AS
 SELECT i.id AS shipment_item_id,i.product_id,s.destination_warehouse_id AS warehouse_id,s.id AS shipment_id,s.shipment_number,s.costs_finalized_at,p.purchase_number,i.purchase_cost_mmk,i.allocated_transport_mmk AS cargo_cost_mmk,i.allocated_expense_mmk AS additional_cost_mmk,i.landed_cost_mmk,i.costing_sellable_quantity AS sellable_quantity
 FROM app.shipment_items i JOIN app.shipments s ON s.id=i.shipment_id JOIN app.purchase_items pi ON pi.id=i.purchase_item_id JOIN app.purchases p ON p.id=pi.purchase_id WHERE s.costs_finalized_at IS NOT NULL AND s.status<>'CANCELLED' AND i.costing_sellable_quantity>0
 UNION ALL
 SELECT i.id,b.product_id,t.to_warehouse_id,s.id,s.shipment_number,s.costs_finalized_at,'Transfer '||t.transfer_number,b.purchase_cost_mmk,b.transport_cost_mmk,b.other_cost_mmk,b.total_cost_mmk,b.sellable_quantity FROM app.stock_transfers t JOIN app.shipments s ON s.id=t.shipment_id JOIN app.stock_transfer_items i ON i.transfer_id=t.id JOIN app.batches b ON b.transfer_item_id=i.id WHERE t.status='RECEIVED' AND b.sellable_quantity>0;
CREATE FUNCTION app.guard_transfer_shipment() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE tr app.stock_transfers; BEGIN
 SELECT * INTO tr FROM app.stock_transfers WHERE shipment_id=OLD.id;
 IF FOUND AND (TG_OP='DELETE' OR NEW.destination_warehouse_id<>tr.to_warehouse_id OR NEW.status<>tr.status OR (NEW.costs_finalized_at IS DISTINCT FROM OLD.costs_finalized_at AND tr.status<>'RECEIVED')) THEN RAISE EXCEPTION 'warehouse transfers must use the controlled dispatch/receipt/cancellation workflow' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER guard_transfer_shipment BEFORE UPDATE OR DELETE ON app.shipments FOR EACH ROW EXECUTE FUNCTION app.guard_transfer_shipment();
CREATE FUNCTION app.protect_dispatched_transfer_item() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE state text; BEGIN
 SELECT status INTO state FROM app.stock_transfers WHERE id=OLD.transfer_id;
 IF state IN('RECEIVED','CANCELLED','REVERSED') OR TG_OP='DELETE' OR NEW.transfer_id<>OLD.transfer_id OR NEW.batch_id<>OLD.batch_id OR NEW.quantity<>OLD.quantity OR NEW.source_unit_cost_mmk IS DISTINCT FROM OLD.source_unit_cost_mmk THEN RAISE EXCEPTION 'dispatched transfer identity and quantities are immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_dispatched_transfer_item BEFORE UPDATE OR DELETE ON app.stock_transfer_items FOR EACH ROW EXECUTE FUNCTION app.protect_dispatched_transfer_item();
-- Follow the preserved batch lineage for supplier returns after one or more legs.
CREATE FUNCTION app.batch_receiving_item(batch uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
 WITH RECURSIVE lineage AS (
 SELECT id,receiving_item_id,source_batch_id FROM app.batches WHERE id=batch
 UNION
 SELECT b.id,b.receiving_item_id,b.source_batch_id FROM app.batches b JOIN lineage l ON b.id=l.source_batch_id)
 SELECT receiving_item_id FROM lineage WHERE receiving_item_id IS NOT NULL LIMIT 1
$$;
DO $$ DECLARE definition text; BEGIN
 definition=pg_get_functiondef('app.purchase_return_post(jsonb,uuid)'::regprocedure);
 IF strpos(definition,'gr.id=pb.receiving_item_id')=0 OR strpos(definition,'gr.id=b.receiving_item_id')=0 THEN RAISE EXCEPTION 'Unexpected supplier return batch lookup'; END IF;
 definition=replace(definition,'gr.id=pb.receiving_item_id','gr.id=app.batch_receiving_item(pb.id)');
 definition=replace(definition,'gr.id=b.receiving_item_id','gr.id=app.batch_receiving_item(b.id)');
 EXECUTE definition;
END $$;
