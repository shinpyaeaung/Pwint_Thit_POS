-- name: DispatchTransfer :one
SELECT app.dispatch_transfer(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: ReceiveTransfer :one
SELECT app.receive_transfer(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: CancelTransfer :exec
SELECT app.cancel_transfer(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid);
-- name: GetTransfer :one
SELECT (jsonb_build_object('id',t.id,'shipment_id',s.id,'transfer_number',t.transfer_number,'from_warehouse_id',t.from_warehouse_id,'to_warehouse_id',t.to_warehouse_id,'from_warehouse',w.name,'status',t.status,'dispatched_at',t.dispatched_at,'received_at',t.received_at,
 'items',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'batch_id',b.id,'product_name',p.name,'sku',p.sku,'base_unit',p.base_unit_code,'batch_number',b.batch_number,'quantity',i.quantity::text,'received_quantity',i.received_quantity::text,'damaged_quantity',i.damaged_quantity::text,'notes',i.notes,'destination_batch_id',dest.id) || CASE WHEN sqlc.arg(costs)::boolean THEN jsonb_build_object('source_unit_cost_mmk',i.source_unit_cost_mmk::text,'destination_unit_cost_mmk',dest.actual_unit_cost_mmk::text) ELSE '{}'::jsonb END ORDER BY i.id) FROM app.stock_transfer_items i JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id LEFT JOIN app.batches dest ON dest.transfer_item_id=i.id WHERE i.transfer_id=t.id),'[]')) || CASE WHEN sqlc.arg(costs)::boolean THEN jsonb_build_object('cost_document',t.cost_document) ELSE '{}'::jsonb END)::jsonb
 FROM app.stock_transfers t JOIN app.shipments s ON s.id=t.shipment_id JOIN app.warehouses w ON w.id=t.from_warehouse_id WHERE s.id=sqlc.arg(shipment_id);
