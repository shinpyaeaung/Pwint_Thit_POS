CREATE OR REPLACE FUNCTION app.dispatch_transfer(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE prior app.stock_transfers; result uuid; shipment uuid; x jsonb; stock app.inventory; batch app.batches; item uuid; qty numeric; carried numeric; unit_cost numeric; origin text;
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
  carried=app.fifo_cost(batch.id,stock.warehouse_id,'SELLABLE',qty);unit_cost=round(carried/qty,8);
  INSERT INTO app.stock_transfer_items(transfer_id,batch_id,quantity,source_unit_cost_mmk,carried_cost_mmk) VALUES(result,batch.id,qty,unit_cost,carried) RETURNING id INTO item;
  INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,stock_transfer_item_id,idempotency_key,occurred_at,recorded_by,reason)
  VALUES(stock.warehouse_id,batch.id,'TRANSFER',-qty,unit_cost,item,'transfer-dispatch:'||item,clock_timestamp(),actor,'Dispatch '||result);
 END LOOP;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'transfers.dispatch','stock_transfers',result,d);
 RETURN shipment;
END $$;

CREATE OR REPLACE FUNCTION app.receive_transfer(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE tr app.stock_transfers; sh app.shipments; item app.stock_transfer_items; source app.batches; x jsonb; result uuid; layer_document jsonb; unit_cost numeric;
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
  carried=coalesce(item.carried_cost_mmk,round(item.source_unit_cost_mmk*item.quantity,4));
  purchase=least(carried,round(source.purchase_cost_mmk/source.sellable_quantity*item.quantity,4));
  transport=least(carried-purchase,round(source.transport_cost_mmk/source.sellable_quantity*item.quantity,4));
  other=carried-purchase-transport;
  SELECT coalesce(source.carton_size,r.carton_size) INTO pack FROM (SELECT 1) seed LEFT JOIN app.goods_receiving_items r ON r.id=source.receiving_item_id;
  UPDATE app.stock_transfer_items SET received_quantity=received,damaged_quantity=damaged,notes=x->>'notes' WHERE id=item.id;
  result=source.id;
  unit_cost=round((carried+allocated_cargo+allocated_extra)/nullif(received-damaged,0),8);
  WITH chunks AS (
   SELECT l.sequence,l.unit_cost_mmk,-m.sellable_delta AS quantity,
    sum(-m.sellable_delta) OVER(ORDER BY l.sequence) AS through_qty,
    coalesce(sum(-m.sellable_delta) OVER(ORDER BY l.sequence ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior_qty
   FROM app.inventory_cost_movements m JOIN app.inventory_movements v ON v.id=m.movement_id JOIN app.inventory_cost_layers l ON l.id=m.layer_id
   WHERE v.idempotency_key='transfer-dispatch:'||item.id
  ), parts AS (
   SELECT *,round((received-damaged)*through_qty/item.quantity,6)-round((received-damaged)*prior_qty/item.quantity,6) AS sq,
    round(damaged*through_qty/item.quantity,6)-round(damaged*prior_qty/item.quantity,6) AS dq,
    round(quantity*unit_cost_mmk,4)+round((allocated_cargo+allocated_extra)*through_qty/item.quantity,4)-round((allocated_cargo+allocated_extra)*prior_qty/item.quantity,4) AS cost FROM chunks
  ), costs AS (SELECT *,sum(CASE WHEN sq=0 THEN cost ELSE 0 END) OVER() AS stranded_cost FROM parts)
  SELECT coalesce(jsonb_agg(jsonb_build_object('sellable',sq::text,'damaged',dq::text,'unit_cost_mmk',CASE WHEN sq>0 THEN round((cost+stranded_cost*sq/nullif(received-damaged,0))/sq,8)::text END) ORDER BY sequence),'[]') INTO layer_document FROM costs WHERE sq>0 OR dq>0;
  -- An in-transit transfer dispatched before this migration has no cost-layer ledger.
  IF layer_document='[]'::jsonb AND received>0 THEN layer_document=jsonb_build_array(jsonb_build_object('sellable',(received-damaged)::text,'damaged',damaged::text,'unit_cost_mmk',unit_cost::text)); END IF;
  UPDATE app.stock_transfer_items SET destination_unit_cost_mmk=unit_cost,destination_cost_layers=layer_document WHERE id=item.id;
  IF received>0 THEN
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,stock_transfer_item_id,idempotency_key,occurred_at,recorded_by,reason)
   SELECT tr.to_warehouse_id,b.id,'TRANSFER',received-damaged,damaged,unit_cost,item.id,'transfer-receive:'||item.id,when_at,actor,coalesce(nullif(x->>'notes',''),'Receive '||tr.transfer_number) FROM app.batches b WHERE b.id=result;
  END IF;
  lines=lines||jsonb_build_array(jsonb_build_object('id',item.id,'batch_id',result,'source_batch_id',source.id,'received_quantity',received::text,'damaged_quantity',damaged::text,'missing_quantity',(item.quantity-received)::text,'carried_cost_mmk',carried::text,'cargo_cost_mmk',allocated_cargo::text,'additional_cost_mmk',allocated_extra::text,'landed_cost_mmk',(carried+allocated_cargo+allocated_extra)::text,'sellable_quantity',(received-damaged)::text));
 END LOOP;
 UPDATE app.stock_transfers SET status='RECEIVED',received_at=when_at,receipt_payload=d,cost_document=jsonb_build_object('items',lines,'cargo_mmk',cargo::text,'additional_mmk',extra::text,'allocation_method','QUANTITY') WHERE id=tr.id;
 UPDATE app.shipments SET status='RECEIVED',arrived_at=when_at,costs_finalized_at=when_at,costs_finalized_by=actor,allocation_method='QUANTITY',version=version+1 WHERE id=sh.id;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'transfers.receive','stock_transfers',tr.id,jsonb_build_object('input',d,'costing',lines));
 RETURN sh.id;
END $$;

