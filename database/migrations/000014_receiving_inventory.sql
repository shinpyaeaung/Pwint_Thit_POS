ALTER TABLE app.goods_receiving ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.goods_receiving ADD COLUMN request_payload jsonb;
CREATE UNIQUE INDEX one_posted_receipt_per_shipment ON app.goods_receiving(shipment_id) WHERE status='POSTED';
ALTER TABLE app.goods_receiving_items ADD COLUMN carton_size numeric(20,6) CHECK(carton_size>0 AND carton_size<>'NaN'::numeric);
ALTER TABLE app.goods_receiving_items ADD COLUMN received_cartons numeric(20,6) NOT NULL DEFAULT 0 CHECK(received_cartons>=0 AND received_cartons<>'NaN'::numeric);
ALTER TABLE app.goods_receiving_items ADD COLUMN received_units numeric(20,6) CHECK(received_units>=0 AND received_units<>'NaN'::numeric);
ALTER TABLE app.inventory ADD COLUMN version bigint NOT NULL DEFAULT 1;
ALTER TABLE app.stock_adjustments ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.stock_adjustments ADD COLUMN request_payload jsonb;
ALTER TABLE app.stock_adjustment_items DROP CONSTRAINT stock_adjustment_items_stock_bucket_check;
ALTER TABLE app.stock_adjustment_items ADD CHECK(stock_bucket IN ('SELLABLE','DAMAGED','RESERVED'));
ALTER TABLE app.stock_adjustment_items ALTER COLUMN unit_cost_mmk DROP NOT NULL;
ALTER TABLE app.stock_adjustment_items ADD CHECK(unit_cost_mmk IS NOT NULL OR stock_bucket<>'SELLABLE');
-- A wholly lost/damaged batch has no sellable unit cost; never invent a zero cost.
ALTER TABLE app.inventory_movements ALTER COLUMN unit_cost_mmk DROP NOT NULL;
ALTER TABLE app.inventory_movements ADD CHECK(unit_cost_mmk IS NOT NULL OR sellable_delta=0);
CREATE FUNCTION app.inventory_write_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR pg_trigger_depth()<2 THEN RAISE EXCEPTION 'inventory can only change through a stock movement' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER inventory_movement_only BEFORE INSERT OR UPDATE OR DELETE ON app.inventory FOR EACH ROW EXECUTE FUNCTION app.inventory_write_guard();
CREATE FUNCTION app.apply_inventory_movement() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE app.inventory SET sellable_quantity=sellable_quantity+NEW.sellable_delta,reserved_quantity=reserved_quantity+NEW.reserved_delta,damaged_quantity=damaged_quantity+NEW.damaged_delta,version=version+1 WHERE warehouse_id=NEW.warehouse_id AND batch_id=NEW.batch_id;
 IF NOT FOUND THEN INSERT INTO app.inventory(warehouse_id,batch_id,sellable_quantity,reserved_quantity,damaged_quantity) VALUES(NEW.warehouse_id,NEW.batch_id,NEW.sellable_delta,NEW.reserved_delta,NEW.damaged_delta); END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER apply_stock AFTER INSERT ON app.inventory_movements FOR EACH ROW EXECUTE FUNCTION app.apply_inventory_movement();
CREATE INDEX receiving_page ON app.goods_receiving(received_at DESC,id);

CREATE FUNCTION app.post_receiving(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE sh app.shipments; si app.shipment_items; prior app.goods_receiving; r uuid; ri uuid; batch uuid; x jsonb; pack numeric; cartons numeric; loose numeric; received numeric; damaged numeric; sellable numeric; cost numeric; count_items int; when_at timestamptz;
BEGIN
 SELECT * INTO prior FROM app.goods_receiving WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF prior.request_payload<>d THEN RAISE EXCEPTION 'receiving: Request already used with different contents.' USING ERRCODE='23514'; END IF; RETURN prior.id; END IF;
 SELECT * INTO sh FROM app.shipments WHERE id=(d->>'shipment_id')::uuid FOR UPDATE;
 SELECT * INTO prior FROM app.goods_receiving WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF prior.request_payload<>d THEN RAISE EXCEPTION 'receiving: Request already used with different contents.' USING ERRCODE='23514'; END IF; RETURN prior.id; END IF;
 IF sh.id IS NULL OR sh.status<>'ARRIVED' OR sh.costs_finalized_at IS NULL OR NOT EXISTS(SELECT 1 FROM app.shipment_costings WHERE shipment_id=sh.id) THEN RAISE EXCEPTION 'receiving: Choose an arrived shipment with finalized landed costs.' USING ERRCODE='23514'; END IF;
 IF sh.version::text<>d->>'version' THEN RAISE EXCEPTION 'receiving: Shipment changed. Reload before posting.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM app.goods_receiving WHERE shipment_id=sh.id AND status NOT IN ('CANCELLED','REVERSED')) THEN RAISE EXCEPTION 'receiving: This shipment already has a receiving record.' USING ERRCODE='23514'; END IF;
 SELECT count(*) INTO count_items FROM app.shipment_items WHERE shipment_id=sh.id;
 IF jsonb_array_length(d->'items')<>count_items OR (SELECT count(DISTINCT value->>'shipment_item_id') FROM jsonb_array_elements(d->'items'))<>count_items THEN RAISE EXCEPTION 'receiving: Include every shipment item exactly once.' USING ERRCODE='23514'; END IF;
 when_at=(d->>'received_at')::timestamptz;
 IF when_at<sh.arrived_at THEN RAISE EXCEPTION 'receiving: Receiving date cannot precede warehouse arrival.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.goods_receiving(receipt_number,shipment_id,warehouse_id,received_at,received_by,notes,request_id,request_payload) VALUES(d->>'receipt_number',sh.id,sh.destination_warehouse_id,when_at,actor,nullif(d->>'notes',''),(d->>'request_id')::uuid,d) RETURNING id INTO r;
 FOR x IN SELECT value FROM jsonb_array_elements(d->'items') LOOP
  SELECT * INTO si FROM app.shipment_items WHERE id=(x->>'shipment_item_id')::uuid AND shipment_id=sh.id;
  IF NOT FOUND OR si.purchase_cost_mmk IS NULL THEN RAISE EXCEPTION 'receiving: Unknown or uncosted shipment item.' USING ERRCODE='23514'; END IF;
  SELECT units_per_pack INTO pack FROM app.product_units WHERE product_id=si.product_id AND unit_code='CARTON' FOR SHARE;
  IF coalesce(pack,0)<>coalesce(nullif(x->>'carton_size','')::numeric,0) THEN RAISE EXCEPTION 'receiving: Carton conversion changed. Reload the receipt.' USING ERRCODE='23514'; END IF;
  cartons=(x->>'received_cartons')::numeric; loose=(x->>'received_units')::numeric; damaged=(x->>'damaged_quantity')::numeric;
  IF pack IS NULL AND cartons<>0 THEN RAISE EXCEPTION 'receiving: This product has no carton conversion.' USING ERRCODE='23514'; END IF;
  received=cartons*coalesce(pack,0)+loose; sellable=received-damaged;
  IF received<>round(received,6) OR received>si.expected_quantity OR damaged>received OR sellable<>si.costing_sellable_quantity THEN RAISE EXCEPTION 'receiving: Received minus damaged must match finalized sellable quantity; received cannot exceed expected. Reconcile discrepancies before posting.' USING ERRCODE='23514'; END IF;
  IF (received<>si.expected_quantity OR damaged>0) AND btrim(coalesce(x->>'notes',''))='' THEN RAISE EXCEPTION 'receiving: Explain missing or damaged quantities in the item notes.' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM app.products WHERE id=si.product_id AND tracks_expiry) AND nullif(x->>'expires_on','') IS NULL THEN RAISE EXCEPTION 'receiving: Expiry date is required for this product.' USING ERRCODE='23514'; END IF;
  INSERT INTO app.goods_receiving_items(goods_receiving_id,shipment_id,shipment_item_id,product_id,expected_quantity,received_quantity,damaged_quantity,batch_number,manufactured_on,expires_on,notes,carton_size,received_cartons,received_units)
  VALUES(r,sh.id,si.id,si.product_id,si.expected_quantity,received,damaged,x->>'batch_number',nullif(x->>'manufactured_on','')::date,nullif(x->>'expires_on','')::date,nullif(x->>'notes',''),pack,cartons,loose) RETURNING id INTO ri;
  INSERT INTO app.batches(product_id,receiving_item_id,batch_number,received_at,manufactured_on,expires_on,purchase_cost_mmk,transport_cost_mmk,other_cost_mmk,sellable_quantity,finalized_at)
  VALUES(si.product_id,ri,x->>'batch_number',when_at,nullif(x->>'manufactured_on','')::date,nullif(x->>'expires_on','')::date,si.purchase_cost_mmk,si.allocated_transport_mmk,si.allocated_expense_mmk,sellable,now()) RETURNING id,actual_unit_cost_mmk INTO batch,cost;
  IF received>0 THEN
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,receiving_item_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(sh.destination_warehouse_id,batch,'RECEIPT',sellable,damaged,cost,ri,'receipt:'||ri,when_at,actor,coalesce(nullif(x->>'notes',''),'Goods received'));
  END IF;
 END LOOP;
 UPDATE app.goods_receiving SET status='POSTED',posted_at=now() WHERE id=r;
 UPDATE app.shipments SET status='RECEIVED',version=version+1 WHERE id=sh.id;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'receiving.post','goods_receiving',r,d);
 RETURN r;
END $$;

CREATE FUNCTION app.adjust_inventory(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.inventory; b app.batches; prior app.stock_adjustments; adjustment uuid; item uuid; delta numeric; bucket text;
BEGIN
 SELECT * INTO prior FROM app.stock_adjustments WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF prior.request_payload<>d THEN RAISE EXCEPTION 'receiving: Request already used with different contents.' USING ERRCODE='23514'; END IF; RETURN prior.id; END IF;
 SELECT * INTO old FROM app.inventory WHERE warehouse_id=(d->>'warehouse_id')::uuid AND batch_id=(d->>'batch_id')::uuid FOR UPDATE;
 SELECT * INTO prior FROM app.stock_adjustments WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF prior.request_payload<>d THEN RAISE EXCEPTION 'receiving: Request already used with different contents.' USING ERRCODE='23514'; END IF; RETURN prior.id; END IF;
 IF old.batch_id IS NULL OR old.version::text<>d->>'version' THEN RAISE EXCEPTION 'receiving: Stock changed. Reload before adjusting.' USING ERRCODE='23514'; END IF;
 SELECT * INTO b FROM app.batches WHERE id=old.batch_id;
 delta=(d->>'quantity_delta')::numeric; bucket=d->>'bucket';
 IF b.finalized_at IS NULL OR delta=0 OR bucket NOT IN ('SELLABLE','DAMAGED','RESERVED') OR (bucket='SELLABLE' AND b.actual_unit_cost_mmk IS NULL) THEN RAISE EXCEPTION 'receiving: Choose a valid non-zero adjustment on a costed batch.' USING ERRCODE='23514'; END IF;
 IF (bucket='SELLABLE' AND old.sellable_quantity+delta<old.reserved_quantity) OR (bucket='DAMAGED' AND old.damaged_quantity+delta<0) OR (bucket='RESERVED' AND (old.reserved_quantity+delta<0 OR old.reserved_quantity+delta>old.sellable_quantity)) THEN RAISE EXCEPTION 'receiving: Adjustment would make stock negative or exceed available stock.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.stock_adjustments(warehouse_id,reason,adjusted_at,created_by,request_id,request_payload) VALUES(old.warehouse_id,d->>'reason',now(),actor,(d->>'request_id')::uuid,d) RETURNING id INTO adjustment;
 INSERT INTO app.stock_adjustment_items(stock_adjustment_id,batch_id,quantity_delta,stock_bucket,unit_cost_mmk) VALUES(adjustment,b.id,delta,bucket,b.actual_unit_cost_mmk) RETURNING id INTO item;
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,reserved_delta,damaged_delta,unit_cost_mmk,stock_adjustment_item_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(old.warehouse_id,b.id,'ADJUSTMENT',CASE WHEN bucket='SELLABLE' THEN delta ELSE 0 END,CASE WHEN bucket='RESERVED' THEN delta ELSE 0 END,CASE WHEN bucket='DAMAGED' THEN delta ELSE 0 END,b.actual_unit_cost_mmk,item,'adjustment:'||adjustment,now(),actor,d->>'reason');
 UPDATE app.stock_adjustments SET status='POSTED',posted_at=now() WHERE id=adjustment;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value,reason) VALUES(actor,'inventory.adjust','stock_adjustments',adjustment,to_jsonb(old),d,d->>'reason');
 RETURN adjustment;
END $$;
