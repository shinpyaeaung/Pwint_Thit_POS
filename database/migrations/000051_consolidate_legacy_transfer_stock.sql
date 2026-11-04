CREATE FUNCTION app.original_batch(batch uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
 WITH RECURSIVE lineage AS (SELECT id,source_batch_id FROM app.batches WHERE id=batch UNION SELECT b.id,b.source_batch_id FROM app.batches b JOIN lineage l ON b.id=l.source_batch_id)
 SELECT id FROM lineage WHERE source_batch_id IS NULL
$$;
-- Reclassify only current physical stock. Historical batches, invoices and movements
-- remain immutable. Each old warehouse cost record becomes a root-batch cost record.
DO $$ DECLARE stock record; layer record; actor uuid; root uuid; adjustment uuid; item uuid; bucket text; qty numeric; target uuid; delta numeric; moment timestamptz=clock_timestamp(); BEGIN
 SELECT id INTO actor FROM app.users WHERE role_code='SUPER_ADMIN' AND is_active ORDER BY created_at,id LIMIT 1;
 FOR stock IN SELECT i.* FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id WHERE b.source_batch_id IS NOT NULL AND (i.sellable_quantity>0 OR i.damaged_quantity>0) ORDER BY i.warehouse_id,i.batch_id LOOP
  IF actor IS NULL THEN RAISE EXCEPTION 'Active Super Admin required for audited transfer consolidation'; END IF;
  root=app.original_batch(stock.batch_id);
  INSERT INTO app.stock_adjustments(warehouse_id,reason,adjusted_at,created_by) VALUES(stock.warehouse_id,'Preserve original batch identity after warehouse transfer',moment,actor) RETURNING id INTO adjustment;
  IF stock.reserved_quantity>0 THEN
   INSERT INTO app.stock_adjustment_items(stock_adjustment_id,batch_id,quantity_delta,stock_bucket) VALUES(adjustment,stock.batch_id,-stock.reserved_quantity,'RESERVED') RETURNING id INTO item;
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,reserved_delta,stock_adjustment_item_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(stock.warehouse_id,stock.batch_id,'ADJUSTMENT',-stock.reserved_quantity,item,'batch-consolidate:'||item,moment,actor,'Relocate reservation with original batch');
  END IF;
  FOR layer IN SELECT * FROM app.inventory_cost_layers WHERE warehouse_id=stock.warehouse_id AND batch_id=stock.batch_id AND (sellable_quantity>0 OR damaged_quantity>0) ORDER BY sequence LOOP
   FOREACH bucket IN ARRAY ARRAY['SELLABLE','DAMAGED'] LOOP
    qty=CASE WHEN bucket='SELLABLE' THEN layer.sellable_quantity ELSE layer.damaged_quantity END;
    IF qty=0 THEN CONTINUE; END IF;
    FOREACH target IN ARRAY ARRAY[stock.batch_id,root] LOOP
     delta=CASE WHEN target=stock.batch_id THEN -qty ELSE qty END;
     INSERT INTO app.stock_adjustment_items(stock_adjustment_id,batch_id,quantity_delta,stock_bucket,unit_cost_mmk) VALUES(adjustment,target,delta,bucket,layer.unit_cost_mmk) RETURNING id INTO item;
     INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,stock_adjustment_item_id,idempotency_key,occurred_at,recorded_by,reason)
     VALUES(stock.warehouse_id,target,'ADJUSTMENT',CASE WHEN bucket='SELLABLE' THEN delta ELSE 0 END,CASE WHEN bucket='DAMAGED' THEN delta ELSE 0 END,layer.unit_cost_mmk,item,'batch-consolidate:'||item,moment,actor,'Consolidate transferred stock into original batch '||root);
    END LOOP;
   END LOOP;
  END LOOP;
  IF stock.reserved_quantity>0 THEN
   INSERT INTO app.stock_adjustment_items(stock_adjustment_id,batch_id,quantity_delta,stock_bucket) VALUES(adjustment,root,stock.reserved_quantity,'RESERVED') RETURNING id INTO item;
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,reserved_delta,stock_adjustment_item_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(stock.warehouse_id,root,'ADJUSTMENT',stock.reserved_quantity,item,'batch-consolidate:'||item,moment,actor,'Preserve relocated reservation');
  END IF;
  UPDATE app.stock_adjustments SET status='POSTED',posted_at=moment WHERE id=adjustment;
  INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value,reason) VALUES(actor,'inventory.consolidate_transfer_batch','stock_adjustments',adjustment,to_jsonb(stock),jsonb_build_object('original_batch_id',root),'Migration: preserve original physical batch and warehouse FIFO costs');
 END LOOP;
END $$;
-- Future returns and reversals against old invoices rejoin the physical batch.
CREATE FUNCTION app.canonical_movement_batch() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 NEW.batch_id=app.original_batch(NEW.batch_id);RETURN NEW;
END $$;
CREATE TRIGGER canonical_batch BEFORE INSERT ON app.inventory_movements FOR EACH ROW EXECUTE FUNCTION app.canonical_movement_batch();

DO $$ DECLARE definition text; BEGIN
 definition=pg_get_functiondef('app.receive_transfer(jsonb,uuid)'::regprocedure);
 definition=replace(definition,'SELECT * INTO source FROM app.batches WHERE id=item.batch_id;','SELECT * INTO source FROM app.batches WHERE id=app.original_batch(item.batch_id);');
 EXECUTE definition;
END $$;
CREATE FUNCTION app.verify_cost_layer_stock() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE stock app.inventory; sellable numeric; damaged numeric; BEGIN
 SELECT * INTO stock FROM app.inventory WHERE batch_id=NEW.batch_id AND warehouse_id=NEW.warehouse_id;
 SELECT coalesce(sum(sellable_quantity),0),coalesce(sum(damaged_quantity),0) INTO sellable,damaged FROM app.inventory_cost_layers WHERE batch_id=NEW.batch_id AND warehouse_id=NEW.warehouse_id AND (sellable_quantity>0 OR damaged_quantity>0);
 IF stock.sellable_quantity<>sellable OR stock.damaged_quantity<>damaged THEN RAISE EXCEPTION 'FIFO cost quantities must reconcile with physical inventory' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER verify_cost_stock AFTER INSERT ON app.inventory_movements FOR EACH ROW EXECUTE FUNCTION app.verify_cost_layer_stock();
