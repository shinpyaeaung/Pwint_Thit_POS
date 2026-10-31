-- Correct remaining manual stock with dated movements, never by editing finalized costs.
CREATE TABLE app.manual_stock_cost_corrections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL UNIQUE,
 warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 old_batch_id uuid NOT NULL REFERENCES app.batches(id), new_batch_id uuid NOT NULL UNIQUE REFERENCES app.batches(id),
 sellable_quantity numeric(20,6) NOT NULL, damaged_quantity numeric(20,6) NOT NULL,
 old_unit_cost_mmk numeric(24,8) NOT NULL, new_unit_cost_mmk numeric(24,8) NOT NULL,
 payload jsonb NOT NULL, reason text NOT NULL, recorded_by uuid NOT NULL REFERENCES app.users(id), corrected_at timestamptz NOT NULL,
 CHECK(old_batch_id<>new_batch_id AND sellable_quantity>=0 AND damaged_quantity>=0 AND sellable_quantity+damaged_quantity>0),
 CHECK(sellable_quantity<>'NaN' AND damaged_quantity<>'NaN' AND old_unit_cost_mmk>=0 AND new_unit_cost_mmk>=0 AND old_unit_cost_mmk<>'NaN' AND new_unit_cost_mmk<>'NaN')
);
CREATE INDEX manual_stock_correction_history ON app.manual_stock_cost_corrections(old_batch_id,warehouse_id,corrected_at);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.manual_stock_cost_corrections FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE FUNCTION app.correct_manual_stock_cost(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE previous app.manual_stock_cost_corrections; source app.batches; stock app.inventory;
 entry uuid; replacement uuid; adjustment uuid; item uuid; correction uuid; cost numeric; total numeric; actual numeric;
 bucket text; qty numeric; target uuid; delta numeric; movement_cost numeric; when_at timestamptz;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.users WHERE id=actor AND role_code='SUPER_ADMIN' AND is_active) THEN
  RAISE EXCEPTION 'receiving: Only Super Admin can correct manual stock cost.' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO previous FROM app.manual_stock_cost_corrections WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
  IF previous.payload<>d OR previous.recorded_by<>actor THEN RAISE EXCEPTION 'receiving: Request already used with different contents.' USING ERRCODE='23514'; END IF;
  RETURN previous.new_batch_id;
 END IF;
 SELECT * INTO source FROM app.batches WHERE id=(d->>'batch_id')::uuid;
 IF NOT FOUND OR source.manual_stock_entry_id IS NULL OR source.finalized_at IS NULL OR source.actual_unit_cost_mmk IS NULL THEN
  RAISE EXCEPTION 'receiving: Choose a costed batch created with Add existing stock.' USING ERRCODE='23514'; END IF;
 -- Same lock order as FIFO checkout: product, then stock. Costs remain immutable.
 PERFORM 1 FROM app.products WHERE id=source.product_id FOR UPDATE;
 SELECT * INTO stock FROM app.inventory WHERE warehouse_id=(d->>'warehouse_id')::uuid AND batch_id=source.id FOR UPDATE;
 IF NOT FOUND OR stock.version::text IS DISTINCT FROM d->>'version' THEN
  RAISE EXCEPTION 'receiving: Stock changed. Reload inventory before correcting cost.' USING ERRCODE='23514'; END IF;
 IF stock.reserved_quantity<>0 THEN RAISE EXCEPTION 'receiving: Release reserved stock before correcting its cost.' USING ERRCODE='23514'; END IF;
 total=stock.sellable_quantity+stock.damaged_quantity;
 cost=(d->>'unit_cost_mmk')::numeric;
 IF total<=0 OR cost IS NULL OR cost<0 OR cost='NaN' OR scale(cost)>4 OR cost>=100000000000000 OR nullif(btrim(d->>'reason'),'') IS NULL OR length(d->>'reason')>2000 THEN
  RAISE EXCEPTION 'receiving: Enter a valid cost and reason for remaining stock.' USING ERRCODE='23514'; END IF;
 IF round(round(total*cost,4)/total,8)=source.actual_unit_cost_mmk THEN RAISE EXCEPTION 'receiving: Enter a different landed cost.' USING ERRCODE='23514'; END IF;
 when_at=clock_timestamp();
 INSERT INTO app.manual_stock_entries(request_id,warehouse_id,product_id,payload,recorded_by)
 VALUES((d->>'request_id')::uuid,stock.warehouse_id,source.product_id,d||jsonb_build_object('correction_of_batch_id',source.id),actor) RETURNING id INTO entry;
 INSERT INTO app.batches(product_id,manual_stock_entry_id,batch_number,received_at,manufactured_on,expires_on,purchase_cost_mmk,sellable_quantity,finalized_at,carton_size)
 VALUES(source.product_id,entry,app.next_business_number('BAT'),source.received_at,source.manufactured_on,source.expires_on,round(total*cost,4),total,when_at,source.carton_size)
 RETURNING id,actual_unit_cost_mmk INTO replacement,actual;
 INSERT INTO app.stock_adjustments(warehouse_id,reason,adjusted_at,created_by)
 VALUES(stock.warehouse_id,'Landed cost correction: '||(d->>'reason'),when_at,actor) RETURNING id INTO adjustment;
 FOREACH bucket IN ARRAY ARRAY['SELLABLE','DAMAGED'] LOOP
  qty=CASE WHEN bucket='SELLABLE' THEN stock.sellable_quantity ELSE stock.damaged_quantity END;
  IF qty=0 THEN CONTINUE; END IF;
  FOREACH target IN ARRAY ARRAY[source.id,replacement] LOOP
   delta=CASE WHEN target=source.id THEN -qty ELSE qty END;
   movement_cost=CASE WHEN target=source.id THEN source.actual_unit_cost_mmk ELSE actual END;
   INSERT INTO app.stock_adjustment_items(stock_adjustment_id,batch_id,quantity_delta,stock_bucket,unit_cost_mmk)
   VALUES(adjustment,target,delta,bucket,movement_cost) RETURNING id INTO item;
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,stock_adjustment_item_id,idempotency_key,occurred_at,recorded_by,reason)
   VALUES(stock.warehouse_id,target,'ADJUSTMENT',CASE WHEN bucket='SELLABLE' THEN delta ELSE 0 END,CASE WHEN bucket='DAMAGED' THEN delta ELSE 0 END,movement_cost,item,'cost-correction:'||item,when_at,actor,'Landed cost correction: '||(d->>'reason'));
  END LOOP;
 END LOOP;
 UPDATE app.stock_adjustments SET status='POSTED',posted_at=when_at WHERE id=adjustment;
 INSERT INTO app.manual_stock_cost_corrections(request_id,warehouse_id,old_batch_id,new_batch_id,sellable_quantity,damaged_quantity,old_unit_cost_mmk,new_unit_cost_mmk,payload,reason,recorded_by,corrected_at)
 VALUES((d->>'request_id')::uuid,stock.warehouse_id,source.id,replacement,stock.sellable_quantity,stock.damaged_quantity,source.actual_unit_cost_mmk,actual,d,d->>'reason',actor,when_at) RETURNING id INTO correction;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value,reason)
 VALUES(actor,'inventory.correct_manual_cost','manual_stock_cost_corrections',correction,
 jsonb_build_object('batch_id',source.id,'unit_cost_mmk',source.actual_unit_cost_mmk::text,'inventory',to_jsonb(stock)),
 jsonb_build_object('batch_id',replacement,'unit_cost_mmk',actual::text,'adjustment_id',adjustment,'input',d),d->>'reason');
 RETURN replacement;
END $$;
