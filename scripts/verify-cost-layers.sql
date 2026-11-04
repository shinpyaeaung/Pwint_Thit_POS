BEGIN READ ONLY;
SELECT 'cost_layers_vs_inventory' AS check_name,count(*) AS violations FROM app.inventory i
LEFT JOIN (SELECT warehouse_id,batch_id,sum(sellable_quantity) sellable,sum(damaged_quantity) damaged FROM app.inventory_cost_layers GROUP BY warehouse_id,batch_id) l USING(warehouse_id,batch_id)
WHERE i.sellable_quantity<>coalesce(l.sellable,0) OR i.damaged_quantity<>coalesce(l.damaged,0);
SELECT 'cost_movement_quantities' AS check_name,count(*) AS violations FROM app.inventory_movements m
JOIN (SELECT movement_id,sum(sellable_delta) sellable,sum(damaged_delta) damaged FROM app.inventory_cost_movements GROUP BY movement_id) c ON c.movement_id=m.id
WHERE m.sellable_delta<>c.sellable OR m.damaged_delta<>c.damaged;
SELECT 'fifo_sale_cost_snapshots' AS check_name,count(*) AS violations FROM app.sale_item_batches b JOIN app.inventory_cost_layers l ON l.id=b.cost_layer_id
WHERE b.batch_id<>l.batch_id OR b.unit_cost_mmk<>l.unit_cost_mmk;
SELECT 'new_transfer_batch_duplication' AS check_name,count(*) AS violations FROM app.stock_transfer_items i JOIN app.batches b ON b.transfer_item_id=i.id WHERE i.destination_cost_layers IS NOT NULL;
ROLLBACK;
