-- Opening/manual stock is a distinct immutable source, never a fabricated purchase.
CREATE TABLE app.manual_stock_entries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL UNIQUE,
 warehouse_id uuid NOT NULL REFERENCES app.warehouses(id), product_id uuid NOT NULL REFERENCES app.products(id),
 payload jsonb NOT NULL, recorded_by uuid NOT NULL REFERENCES app.users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.manual_stock_entries FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
ALTER TABLE app.batches ADD COLUMN manual_stock_entry_id uuid UNIQUE REFERENCES app.manual_stock_entries(id);
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='app.batches'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%num_nonnulls(receiving_item_id, transfer_item_id)%' LOOP
 EXECUTE format('ALTER TABLE app.batches DROP CONSTRAINT %I',c.conname); END LOOP;
END $$;
ALTER TABLE app.batches ADD CHECK(num_nonnulls(receiving_item_id,transfer_item_id,manual_stock_entry_id)=1 AND ((transfer_item_id IS NULL)=(source_batch_id IS NULL)));
CREATE OR REPLACE FUNCTION app.manual_stock_post(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.manual_stock_entries; product app.products; entry uuid; batch uuid; adjustment uuid; item uuid;
 qty numeric; pack numeric; unit_cost numeric; retail numeric; wholesale numeric; received timestamptz; expiry date; previous_prices jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.users WHERE id=actor AND role_code='SUPER_ADMIN' AND is_active) THEN RAISE EXCEPTION 'receiving: Only Super Admin can add stock without a purchase.' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.manual_stock_entries WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF old.payload<>d OR old.recorded_by<>actor THEN RAISE EXCEPTION 'receiving: Request already used.' USING ERRCODE='23514'; END IF; RETURN old.id; END IF;
 SELECT * INTO product FROM app.products WHERE id=(d->>'product_id')::uuid AND is_active AND archived_at IS NULL FOR UPDATE;
 IF NOT FOUND OR product.version::text IS DISTINCT FROM d->>'version' THEN RAISE EXCEPTION 'receiving: Product changed. Reopen stock entry and confirm its packaging.' USING ERRCODE='23514'; END IF;
 PERFORM 1 FROM app.warehouses WHERE id=(d->>'warehouse_id')::uuid AND is_active FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'receiving: Choose an active warehouse.' USING ERRCODE='23514'; END IF;
 SELECT units_per_pack INTO pack FROM app.product_units WHERE product_id=product.id AND unit_code=d->>'unit_code';
 qty=(d->>'quantity')::numeric; unit_cost=(d->>'unit_cost_mmk')::numeric; retail=(d->>'retail_price_mmk')::numeric; wholesale=(d->>'wholesale_price_mmk')::numeric;
 received=(d->>'received_at')::timestamptz; expiry=nullif(d->>'expires_on','')::date;
 IF pack IS NULL OR qty IS NULL OR qty<=0 OR qty='NaN' OR scale(qty)>6 OR unit_cost IS NULL OR unit_cost<0 OR unit_cost='NaN' OR scale(unit_cost)>4 OR retail IS NULL OR retail<=0 OR retail='NaN' OR wholesale IS NULL OR wholesale<=0 OR wholesale='NaN' OR received IS NULL OR received>now() OR nullif(btrim(d->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'receiving: Enter quantity, actual cost, selling prices, date and reason.' USING ERRCODE='23514'; END IF;
 IF product.tracks_expiry AND (expiry IS NULL OR expiry<(received AT TIME ZONE 'Asia/Yangon')::date) THEN RAISE EXCEPTION 'receiving: Enter a valid expiry date.' USING ERRCODE='23514'; END IF;
 IF round(qty*pack,6)<>qty*pack THEN RAISE EXCEPTION 'receiving: Quantity exceeds stock precision.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.manual_stock_entries(request_id,warehouse_id,product_id,payload,recorded_by) VALUES((d->>'request_id')::uuid,(d->>'warehouse_id')::uuid,product.id,d,actor) RETURNING id INTO entry;
 INSERT INTO app.batches(product_id,manual_stock_entry_id,batch_number,received_at,expires_on,purchase_cost_mmk,sellable_quantity,finalized_at,carton_size)
 VALUES(product.id,entry,app.next_business_number('BAT'),received,expiry,round(qty*pack*unit_cost,4),qty*pack,now(),(SELECT units_per_pack FROM app.product_units WHERE product_id=product.id AND unit_code='CARTON')) RETURNING id INTO batch;
 INSERT INTO app.stock_adjustments(warehouse_id,reason,adjusted_at,created_by) VALUES((d->>'warehouse_id')::uuid,d->>'reason',received,actor) RETURNING id INTO adjustment;
 INSERT INTO app.stock_adjustment_items(stock_adjustment_id,batch_id,quantity_delta,stock_bucket,unit_cost_mmk) SELECT adjustment,batch,qty*pack,'SELLABLE',actual_unit_cost_mmk FROM app.batches WHERE id=batch RETURNING id INTO item;
 INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,stock_adjustment_item_id,idempotency_key,occurred_at,recorded_by,reason)
 SELECT (d->>'warehouse_id')::uuid,batch,'ADJUSTMENT',qty*pack,actual_unit_cost_mmk,item,'manual:'||entry,received,actor,d->>'reason' FROM app.batches WHERE id=batch;
 UPDATE app.stock_adjustments SET status='POSTED',posted_at=now() WHERE id=adjustment;
 SELECT jsonb_agg(to_jsonb(wp)) INTO previous_prices FROM app.warehouse_prices wp WHERE wp.warehouse_id=(d->>'warehouse_id')::uuid AND wp.product_id=product.id;
 INSERT INTO app.warehouse_prices(warehouse_id,product_id,unit_code,retail_price_mmk,wholesale_price_mmk)
 SELECT (d->>'warehouse_id')::uuid,product.id,u.unit_code,round(retail*u.units_per_pack,4),round(wholesale*u.units_per_pack,4) FROM app.product_units u WHERE u.product_id=product.id
 ON CONFLICT(warehouse_id,product_id,unit_code) DO UPDATE SET retail_price_mmk=excluded.retail_price_mmk,wholesale_price_mmk=excluded.wholesale_price_mmk;
 UPDATE app.products SET version=version+1 WHERE id=product.id;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value,reason) VALUES(actor,'inventory.manual_stock','manual_stock_entries',entry,previous_prices,jsonb_build_object('input',d,'batch_id',batch,'adjustment_id',adjustment),d->>'reason');
 RETURN entry;
END $$;
-- Manual batches can be used in the same later price editor as received batches.
CREATE OR REPLACE VIEW app.warehouse_pricing_costs AS

 SELECT i.id AS shipment_item_id,i.product_id,s.destination_warehouse_id AS warehouse_id,s.id AS shipment_id,s.shipment_number,s.costs_finalized_at,p.purchase_number,i.purchase_cost_mmk,i.allocated_transport_mmk AS cargo_cost_mmk,i.allocated_expense_mmk AS additional_cost_mmk,i.landed_cost_mmk,i.costing_sellable_quantity AS sellable_quantity
 FROM app.shipment_items i JOIN app.shipments s ON s.id=i.shipment_id JOIN app.purchase_items pi ON pi.id=i.purchase_item_id JOIN app.purchases p ON p.id=pi.purchase_id WHERE s.costs_finalized_at IS NOT NULL AND s.status<>'CANCELLED' AND i.costing_sellable_quantity>0
 UNION ALL
 SELECT i.id,b.product_id,t.to_warehouse_id,s.id,s.shipment_number,s.costs_finalized_at,'Transfer '||t.transfer_number,b.purchase_cost_mmk,b.transport_cost_mmk,b.other_cost_mmk,b.total_cost_mmk,b.sellable_quantity FROM app.stock_transfers t JOIN app.shipments s ON s.id=t.shipment_id JOIN app.stock_transfer_items i ON i.transfer_id=t.id JOIN app.batches b ON b.transfer_item_id=i.id WHERE t.status='RECEIVED' AND b.sellable_quantity>0
 UNION ALL SELECT b.id,b.product_id,e.warehouse_id,NULL::uuid,'Manual stock',b.finalized_at,'Manual stock',b.purchase_cost_mmk,b.transport_cost_mmk,b.other_cost_mmk,b.total_cost_mmk,b.sellable_quantity FROM app.batches b JOIN app.manual_stock_entries e ON e.id=b.manual_stock_entry_id;

ALTER FUNCTION app.adjust_inventory(jsonb,uuid) RENAME TO adjust_inventory_before_manual;
CREATE OR REPLACE FUNCTION app.adjust_inventory(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
 IF (d->>'quantity_delta')::numeric>0 AND d->>'bucket'<>'RESERVED' AND NOT EXISTS(SELECT 1 FROM app.users WHERE id=actor AND role_code='SUPER_ADMIN' AND is_active) THEN RAISE EXCEPTION 'receiving: Only Super Admin can manually add stock.' USING ERRCODE='23514'; END IF;
 RETURN app.adjust_inventory_before_manual(d,actor);
END $$;
