-- Preserve chronological FIFO when several pre-existing transfer batches are consolidated.
ALTER TABLE app.inventory_cost_layers ADD COLUMN fifo_received_at timestamptz NOT NULL DEFAULT clock_timestamp();
DROP TRIGGER guard_cost_layer ON app.inventory_cost_layers;
UPDATE app.inventory_cost_layers l SET fifo_received_at=coalesce(
 (SELECT b.received_at FROM app.inventory_movements m JOIN app.stock_adjustment_items a ON a.id=m.stock_adjustment_item_id JOIN app.audit_logs audit ON audit.entity_id=a.stock_adjustment_id AND audit.action='inventory.consolidate_transfer_batch' JOIN app.batches b ON b.id=(audit.old_value->>'batch_id')::uuid WHERE m.id=l.origin_movement_id),
 (SELECT occurred_at FROM app.inventory_movements WHERE id=l.origin_movement_id),
 (SELECT received_at FROM app.batches WHERE id=l.batch_id));
CREATE TRIGGER guard_cost_layer BEFORE INSERT OR UPDATE OR DELETE ON app.inventory_cost_layers FOR EACH ROW EXECUTE FUNCTION app.guard_cost_layer();
DROP INDEX app.inventory_cost_layers_fifo;
CREATE INDEX inventory_cost_layers_fifo ON app.inventory_cost_layers(warehouse_id,batch_id,fifo_received_at,sequence) WHERE sellable_quantity>0 OR damaged_quantity>0;
DO $$ DECLARE definition text; fname text; BEGIN
 FOREACH fname IN ARRAY ARRAY['app.track_inventory_cost()','app.fifo_cost(uuid,uuid,text,numeric)','app.receive_transfer(jsonb,uuid)'] LOOP
  definition=pg_get_functiondef(fname::regprocedure);
  definition=replace(definition,'ORDER BY sequence','ORDER BY fifo_received_at,sequence');
  definition=replace(definition,'ORDER BY l.sequence','ORDER BY l.fifo_received_at,l.sequence');
  IF fname='app.track_inventory_cost()' THEN
   definition=replace(definition,'damaged_quantity,origin_movement_id)','damaged_quantity,origin_movement_id,fifo_received_at)');
   definition=replace(definition,'0,0,NEW.id)','0,0,NEW.id,NEW.occurred_at)');
  END IF;
  IF fname='app.receive_transfer(jsonb,uuid)' THEN
   definition=replace(definition,'WHERE transfer_id=tr.id ORDER BY id LOOP','WHERE transfer_id=tr.id ORDER BY app.original_batch(batch_id),id LOOP');
   definition=replace(definition,'SELECT l.sequence,l.unit_cost_mmk','SELECT l.fifo_received_at,l.sequence,l.unit_cost_mmk');
  END IF;
  EXECUTE definition;
 END LOOP;
END $$;
CREATE OR REPLACE VIEW app.pos_eligible_stock AS
 WITH layers AS (SELECT l.*,coalesce(sum(l.sellable_quantity) OVER(PARTITION BY l.warehouse_id,l.batch_id ORDER BY fifo_received_at,sequence ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior FROM app.inventory_cost_layers l WHERE l.sellable_quantity>0)
 SELECT i.warehouse_id,i.batch_id,l.sellable_quantity,0::numeric(20,6) AS reserved_quantity,l.damaged_quantity,
 least(l.sellable_quantity,greatest(i.available_quantity-l.prior,0))::numeric(20,6) AS available_quantity,i.created_at,i.updated_at,i.version,
 b.product_id,b.received_at,b.expires_on,l.unit_cost_mmk AS actual_unit_cost_mmk,l.id AS cost_layer_id,row_number() OVER(PARTITION BY l.warehouse_id,l.batch_id ORDER BY l.fifo_received_at,l.sequence) AS cost_sequence
 FROM app.inventory i JOIN layers l ON l.batch_id=i.batch_id AND l.warehouse_id=i.warehouse_id JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id
 WHERE i.available_quantity>l.prior AND b.finalized_at IS NOT NULL AND l.unit_cost_mmk IS NOT NULL AND (b.expires_on IS NULL OR b.expires_on>=app.business_date()) AND (NOT p.tracks_expiry OR b.expires_on IS NOT NULL);
CREATE OR REPLACE VIEW app.pos_damaged_stock AS
 SELECT i.warehouse_id,i.batch_id,l.damaged_quantity AS available_quantity,b.product_id,b.received_at,l.unit_cost_mmk AS actual_unit_cost_mmk,l.id AS cost_layer_id,row_number() OVER(PARTITION BY l.warehouse_id,l.batch_id ORDER BY l.fifo_received_at,l.sequence) AS cost_sequence
 FROM app.inventory i JOIN app.inventory_cost_layers l ON l.batch_id=i.batch_id AND l.warehouse_id=i.warehouse_id JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id
 WHERE l.damaged_quantity>0 AND b.finalized_at IS NOT NULL AND l.unit_cost_mmk IS NOT NULL AND (b.expires_on IS NULL OR b.expires_on>=app.business_date()) AND (NOT p.tracks_expiry OR b.expires_on IS NOT NULL);
