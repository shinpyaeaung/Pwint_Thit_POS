-- Keep all valuation consumers on warehouse-specific FIFO cost records.
DO $$ DECLARE definition text; fname text; BEGIN
 FOREACH fname IN ARRAY ARRAY['stock_issue','purchase_return_post_before_accounts'] LOOP
  definition=pg_get_functiondef(format('app.%I(jsonb,uuid)',fname)::regprocedure);
  definition=replace(definition,'round(qty*b.actual_unit_cost_mmk,4)', 'app.fifo_cost(b.id,i.warehouse_id,bucket,qty)');
  -- The movement's cost is a summary; its immutable cost allocations retain each exact FIFO price.
  definition=replace(definition,'damage_delta,b.actual_unit_cost_mmk,','damage_delta,round(app.fifo_cost(b.id,i.warehouse_id,bucket,qty)/qty,8),');
  definition=replace(definition,'END,b.actual_unit_cost_mmk,item','END,round(app.fifo_cost(b.id,i.warehouse_id,bucket,qty)/qty,8),item');
  IF fname='stock_issue' THEN definition=replace(definition,' IF kind=''DAMAGE'' THEN',' b.actual_unit_cost_mmk=round(app.fifo_cost(b.id,i.warehouse_id,bucket,qty)/qty,8); IF kind=''DAMAGE'' THEN'); END IF;
  EXECUTE definition;
 END LOOP;
 definition=pg_get_functiondef('app.adjust_inventory(jsonb,uuid)'::regprocedure);
 definition=replace(definition,$a$delta=(d->>'quantity_delta')::numeric; bucket=d->>'bucket';$a$,$a$delta=(d->>'quantity_delta')::numeric; bucket=d->>'bucket'; b.actual_unit_cost_mmk=coalesce(CASE WHEN delta<0 THEN round(app.fifo_cost(b.id,old.warehouse_id,bucket,-delta)/(-delta),8) ELSE app.inventory_cost(b.id,old.warehouse_id,bucket) END,(SELECT unit_cost_mmk FROM app.inventory_cost_layers WHERE batch_id=b.id AND warehouse_id=old.warehouse_id AND unit_cost_mmk IS NOT NULL ORDER BY sequence DESC LIMIT 1),b.actual_unit_cost_mmk);$a$);
 EXECUTE definition;
 definition=pg_get_functiondef('app.correct_manual_stock_cost(jsonb,uuid)'::regprocedure);
 definition=replace(definition,'total=stock.sellable_quantity+stock.damaged_quantity;', 'total=stock.sellable_quantity+stock.damaged_quantity; source.actual_unit_cost_mmk=coalesce(app.inventory_cost(source.id,stock.warehouse_id),app.inventory_cost(source.id,stock.warehouse_id,''DAMAGED''),source.actual_unit_cost_mmk);');
 EXECUTE definition;
 definition=pg_get_functiondef('app.dashboard(jsonb)'::regprocedure);
 definition=replace(definition,'i.sellable_quantity*b.actual_unit_cost_mmk','(SELECT sum(l.sellable_quantity*l.unit_cost_mmk) FROM app.inventory_cost_layers l WHERE l.batch_id=b.id AND l.warehouse_id=i.warehouse_id AND l.sellable_quantity>0)');
 EXECUTE definition;
END $$;
CREATE OR REPLACE VIEW app.warehouse_pricing_costs AS
 SELECT i.id AS shipment_item_id,i.product_id,s.destination_warehouse_id AS warehouse_id,s.id AS shipment_id,s.shipment_number,s.costs_finalized_at,p.purchase_number,i.purchase_cost_mmk,i.allocated_transport_mmk AS cargo_cost_mmk,i.allocated_expense_mmk AS additional_cost_mmk,i.landed_cost_mmk,i.costing_sellable_quantity AS sellable_quantity
 FROM app.shipment_items i JOIN app.shipments s ON s.id=i.shipment_id JOIN app.purchase_items pi ON pi.id=i.purchase_item_id JOIN app.purchases p ON p.id=pi.purchase_id WHERE s.costs_finalized_at IS NOT NULL AND s.status<>'CANCELLED' AND i.costing_sellable_quantity>0
 UNION ALL
 SELECT i.id,b.product_id,t.to_warehouse_id,s.id,s.shipment_number,s.costs_finalized_at,'Transfer '||t.transfer_number,b.purchase_cost_mmk,b.transport_cost_mmk,b.other_cost_mmk,b.total_cost_mmk,b.sellable_quantity FROM app.stock_transfers t JOIN app.shipments s ON s.id=t.shipment_id JOIN app.stock_transfer_items i ON i.transfer_id=t.id JOIN app.batches b ON b.transfer_item_id=i.id WHERE t.status='RECEIVED' AND b.sellable_quantity>0
 UNION ALL
 SELECT i.id,b.product_id,t.to_warehouse_id,s.id,s.shipment_number,s.costs_finalized_at,'Transfer '||t.transfer_number,
 coalesce(i.carried_cost_mmk,round(i.quantity*i.source_unit_cost_mmk,4))::numeric(20,4),(d->>'cargo_cost_mmk')::numeric(20,4),(d->>'additional_cost_mmk')::numeric(20,4),(d->>'landed_cost_mmk')::numeric(20,4),(i.received_quantity-i.damaged_quantity)::numeric(20,6)
 FROM app.stock_transfers t JOIN app.shipments s ON s.id=t.shipment_id JOIN app.stock_transfer_items i ON i.transfer_id=t.id JOIN app.batches b ON b.id=i.batch_id
 CROSS JOIN LATERAL jsonb_array_elements(t.cost_document->'items') d
 WHERE t.status='RECEIVED' AND i.destination_cost_layers IS NOT NULL AND d->>'id'=i.id::text AND i.received_quantity>i.damaged_quantity;
