-- Physical batch identity is independent of warehouse FIFO cost records.
CREATE TABLE app.inventory_cost_layers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),batch_id uuid NOT NULL REFERENCES app.batches(id),
 sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
 unit_cost_mmk numeric(24,8) CHECK(unit_cost_mmk>=0 AND unit_cost_mmk<>'NaN'),
 sellable_quantity numeric(20,6) NOT NULL CHECK(sellable_quantity>=0 AND sellable_quantity<>'NaN'),
 damaged_quantity numeric(20,6) NOT NULL CHECK(damaged_quantity>=0 AND damaged_quantity<>'NaN'),
 origin_movement_id uuid REFERENCES app.inventory_movements(id),created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX inventory_cost_layers_fifo ON app.inventory_cost_layers(warehouse_id,batch_id,sequence) WHERE sellable_quantity>0 OR damaged_quantity>0;
INSERT INTO app.inventory_cost_layers(warehouse_id,batch_id,unit_cost_mmk,sellable_quantity,damaged_quantity)
SELECT i.warehouse_id,i.batch_id,b.actual_unit_cost_mmk,i.sellable_quantity,i.damaged_quantity FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id WHERE i.sellable_quantity>0 OR i.damaged_quantity>0;
CREATE TABLE app.inventory_cost_movements (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,movement_id uuid NOT NULL REFERENCES app.inventory_movements(id),layer_id uuid NOT NULL REFERENCES app.inventory_cost_layers(id),
 sellable_delta numeric(20,6) NOT NULL,damaged_delta numeric(20,6) NOT NULL,UNIQUE(movement_id,layer_id)
);
CREATE INDEX inventory_cost_movement_layer ON app.inventory_cost_movements(layer_id,id);
CREATE TRIGGER immutable_cost_movement BEFORE UPDATE OR DELETE ON app.inventory_cost_movements FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
ALTER TABLE app.sale_item_batches DROP CONSTRAINT sale_item_batches_sale_item_id_batch_id_key;
ALTER TABLE app.sale_item_batches ADD COLUMN cost_layer_id uuid REFERENCES app.inventory_cost_layers(id);
ALTER TABLE app.stock_transfer_items ADD COLUMN carried_cost_mmk numeric(20,4);
ALTER TABLE app.stock_transfer_items ADD COLUMN destination_unit_cost_mmk numeric(24,8);
ALTER TABLE app.stock_transfer_items ADD COLUMN destination_cost_layers jsonb;

CREATE FUNCTION app.apply_cost_layer_delta(layer uuid,movement uuid,sellable numeric,damaged numeric) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 UPDATE app.inventory_cost_layers SET sellable_quantity=sellable_quantity+sellable,damaged_quantity=damaged_quantity+damaged WHERE id=layer;
 INSERT INTO app.inventory_cost_movements(movement_id,layer_id,sellable_delta,damaged_delta) VALUES(movement,layer,sellable,damaged);
END $$;
-- Cost records are immutable except for movement-controlled remaining quantities.
CREATE FUNCTION app.guard_cost_layer() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF pg_trigger_depth()<2 OR TG_OP='DELETE' THEN RAISE EXCEPTION 'cost layers require an inventory movement' USING ERRCODE='23514'; END IF;
 IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'sellable_quantity'-'damaged_quantity') IS DISTINCT FROM (to_jsonb(OLD)-'sellable_quantity'-'damaged_quantity') THEN RAISE EXCEPTION 'cost layer identity and price are immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER guard_cost_layer BEFORE INSERT OR UPDATE OR DELETE ON app.inventory_cost_layers FOR EACH ROW EXECUTE FUNCTION app.guard_cost_layer();
CREATE FUNCTION app.track_inventory_cost() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE l app.inventory_cost_layers; required numeric; take numeric; bucket text; chosen uuid; entry jsonb; new_layer uuid; restored record; moved boolean=false;
BEGIN
 -- apply_stock has already locked and updated the aggregate inventory position.
 IF NEW.reverses_movement_id IS NOT NULL AND EXISTS(SELECT 1 FROM app.inventory_cost_movements WHERE movement_id=NEW.reverses_movement_id) THEN
  FOR restored IN SELECT * FROM app.inventory_cost_movements WHERE movement_id=NEW.reverses_movement_id ORDER BY layer_id LOOP
   PERFORM app.apply_cost_layer_delta(restored.layer_id,NEW.id,-restored.sellable_delta,-restored.damaged_delta);
  END LOOP;
  RETURN NEW;
 END IF;
 IF NEW.sale_item_batch_id IS NOT NULL THEN SELECT cost_layer_id INTO chosen FROM app.sale_item_batches WHERE id=NEW.sale_item_batch_id; END IF;
 FOREACH bucket IN ARRAY ARRAY['SELLABLE','DAMAGED'] LOOP
  required=greatest(0,-CASE WHEN bucket='SELLABLE' THEN NEW.sellable_delta ELSE NEW.damaged_delta END);
  FOR l IN SELECT * FROM app.inventory_cost_layers WHERE warehouse_id=NEW.warehouse_id AND batch_id=NEW.batch_id
   AND (sellable_quantity>0 OR damaged_quantity>0) AND (chosen IS NULL OR id=chosen) AND CASE WHEN bucket='SELLABLE' THEN sellable_quantity ELSE damaged_quantity END>0 ORDER BY sequence FOR UPDATE LOOP
   EXIT WHEN required=0;
   take=least(required,CASE WHEN bucket='SELLABLE' THEN l.sellable_quantity ELSE l.damaged_quantity END);
   IF NEW.sellable_delta=-NEW.damaged_delta AND NEW.sellable_delta<0 THEN
    PERFORM app.apply_cost_layer_delta(l.id,NEW.id,-take,take);moved=true;
   ELSE
    PERFORM app.apply_cost_layer_delta(l.id,NEW.id,CASE WHEN bucket='SELLABLE' THEN -take ELSE 0 END,CASE WHEN bucket='DAMAGED' THEN -take ELSE 0 END);
   END IF;
   required=required-take;
  END LOOP;
  IF required>0 THEN RAISE EXCEPTION 'insufficient FIFO cost stock' USING ERRCODE='23514'; END IF;
 END LOOP;
 IF moved OR (NEW.sellable_delta<=0 AND NEW.damaged_delta<=0) THEN RETURN NEW; END IF;
 IF NEW.stock_transfer_item_id IS NOT NULL AND NEW.idempotency_key='transfer-receive:'||NEW.stock_transfer_item_id THEN
  FOR entry IN SELECT value FROM app.stock_transfer_items t CROSS JOIN LATERAL jsonb_array_elements(t.destination_cost_layers) WHERE t.id=NEW.stock_transfer_item_id LOOP
   INSERT INTO app.inventory_cost_layers(warehouse_id,batch_id,unit_cost_mmk,sellable_quantity,damaged_quantity,origin_movement_id)
   VALUES(NEW.warehouse_id,NEW.batch_id,(entry->>'unit_cost_mmk')::numeric,0,0,NEW.id) RETURNING id INTO new_layer;
   PERFORM app.apply_cost_layer_delta(new_layer,NEW.id,(entry->>'sellable')::numeric,(entry->>'damaged')::numeric);
  END LOOP;
 ELSE
  INSERT INTO app.inventory_cost_layers(warehouse_id,batch_id,unit_cost_mmk,sellable_quantity,damaged_quantity,origin_movement_id)
  VALUES(NEW.warehouse_id,NEW.batch_id,NEW.unit_cost_mmk,0,0,NEW.id) RETURNING id INTO new_layer;
  PERFORM app.apply_cost_layer_delta(new_layer,NEW.id,greatest(NEW.sellable_delta,0),greatest(NEW.damaged_delta,0));
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER track_cost AFTER INSERT ON app.inventory_movements FOR EACH ROW EXECUTE FUNCTION app.track_inventory_cost();

CREATE FUNCTION app.inventory_cost(batch uuid,warehouse uuid,bucket text DEFAULT 'SELLABLE') RETURNS numeric LANGUAGE sql STABLE AS $$
 SELECT round(sum(unit_cost_mmk*CASE WHEN bucket='SELLABLE' THEN sellable_quantity ELSE damaged_quantity END)/nullif(sum(CASE WHEN bucket='SELLABLE' THEN sellable_quantity ELSE damaged_quantity END),0),8)
 FROM app.inventory_cost_layers WHERE batch_id=batch AND warehouse_id=warehouse AND (sellable_quantity>0 OR damaged_quantity>0)
$$;
CREATE FUNCTION app.fifo_cost(batch uuid,warehouse uuid,bucket text,quantity numeric) RETURNS numeric LANGUAGE sql STABLE AS $$
 WITH ordered AS(SELECT *,CASE WHEN bucket='SELLABLE' THEN sellable_quantity ELSE damaged_quantity END AS qty,
 coalesce(sum(CASE WHEN bucket='SELLABLE' THEN sellable_quantity ELSE damaged_quantity END) OVER(ORDER BY sequence ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior FROM app.inventory_cost_layers WHERE batch_id=batch AND warehouse_id=warehouse AND (sellable_quantity>0 OR damaged_quantity>0))
 SELECT sum(round(least(qty,greatest(quantity-prior,0))*unit_cost_mmk,4)) FROM ordered WHERE prior<quantity
$$;
CREATE OR REPLACE VIEW app.pos_eligible_stock AS
 WITH layers AS (SELECT l.*,coalesce(sum(l.sellable_quantity) OVER(PARTITION BY l.warehouse_id,l.batch_id ORDER BY sequence ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior FROM app.inventory_cost_layers l WHERE l.sellable_quantity>0)
 SELECT i.warehouse_id,i.batch_id,l.sellable_quantity,0::numeric(20,6) AS reserved_quantity,l.damaged_quantity,
 least(l.sellable_quantity,greatest(i.available_quantity-l.prior,0))::numeric(20,6) AS available_quantity,i.created_at,i.updated_at,i.version,
 b.product_id,b.received_at,b.expires_on,l.unit_cost_mmk AS actual_unit_cost_mmk,l.id AS cost_layer_id,l.sequence AS cost_sequence
 FROM app.inventory i JOIN layers l ON l.batch_id=i.batch_id AND l.warehouse_id=i.warehouse_id JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id
 WHERE i.available_quantity>l.prior AND b.finalized_at IS NOT NULL AND l.unit_cost_mmk IS NOT NULL AND (b.expires_on IS NULL OR b.expires_on>=app.business_date()) AND (NOT p.tracks_expiry OR b.expires_on IS NOT NULL);
CREATE OR REPLACE VIEW app.pos_damaged_stock AS
 SELECT i.warehouse_id,i.batch_id,l.damaged_quantity AS available_quantity,b.product_id,b.received_at,l.unit_cost_mmk AS actual_unit_cost_mmk,l.id AS cost_layer_id,l.sequence AS cost_sequence
 FROM app.inventory i JOIN app.inventory_cost_layers l ON l.batch_id=i.batch_id AND l.warehouse_id=i.warehouse_id JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id
 WHERE l.damaged_quantity>0 AND b.finalized_at IS NOT NULL AND l.unit_cost_mmk IS NOT NULL AND (b.expires_on IS NULL OR b.expires_on>=app.business_date()) AND (NOT p.tracks_expiry OR b.expires_on IS NOT NULL);
DO $$ DECLARE definition text; BEGIN
 definition=pg_get_functiondef('app.pos_sale_before_accounts(jsonb,uuid,boolean,boolean,boolean)'::regprocedure);
 definition=replace(definition,'SELECT batch_id,available_quantity,actual_unit_cost_mmk,received_at FROM app.pos_', 'SELECT batch_id,available_quantity,actual_unit_cost_mmk,received_at,cost_layer_id,cost_sequence FROM app.pos_');
 definition=replace(definition,'a->>''batch_id''=stock.batch_id::text','a->>''cost_layer_id''=stock.cost_layer_id::text');
 definition=replace(definition,'ORDER BY received_at,batch_id LOOP','ORDER BY received_at,batch_id,cost_sequence LOOP');
 definition=replace(definition,'''batch_id'',stock.batch_id,''quantity''','''batch_id'',stock.batch_id,''cost_layer_id'',stock.cost_layer_id,''quantity''');
 definition=replace(definition,'sale_item_batches(sale_item_id,batch_id,product_id,quantity,unit_cost_mmk)','sale_item_batches(sale_item_id,batch_id,product_id,quantity,unit_cost_mmk,cost_layer_id)');
 definition=replace(definition,'(alloc->>''unit_cost_mmk'')::numeric) RETURNING id INTO sale_batch;','(alloc->>''unit_cost_mmk'')::numeric,(alloc->>''cost_layer_id'')::uuid) RETURNING id INTO sale_batch;');
 EXECUTE definition;
END $$;
