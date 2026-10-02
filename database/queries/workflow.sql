-- name: PurchaseWorkflow :one
SELECT jsonb_build_object(
 'choices',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',i.id,'purchase_number',p.purchase_number,'supplier_name',s.name,'product_name',coalesce(i.product_name_snapshot,pr.name),'sku',coalesce(i.sku_snapshot,pr.sku),'base_quantity',i.base_quantity::text,'available_quantity',(i.base_quantity-COALESCE((SELECT sum(si.expected_quantity) FROM app.shipment_items si JOIN app.shipments sh ON sh.id=si.shipment_id WHERE si.purchase_item_id=i.id AND sh.status<>'CANCELLED'),0))::text) ORDER BY i.line_number) FROM app.purchase_items i JOIN app.products pr ON pr.id=i.product_id JOIN app.suppliers s ON s.id=p.supplier_id WHERE i.purchase_id=p.id),'[]'::jsonb),
 'shipments',COALESCE((SELECT jsonb_agg(app.shipment_document(sh,sqlc.arg(costs)::boolean) || jsonb_build_object('receipt_id',(SELECT id FROM app.goods_receiving WHERE shipment_id=sh.id AND status='POSTED'),'receipt_number',(SELECT receipt_number FROM app.goods_receiving WHERE shipment_id=sh.id AND status='POSTED')) ORDER BY sh.created_at,sh.id) FROM app.shipments sh WHERE EXISTS(SELECT 1 FROM app.shipment_items si JOIN app.purchase_items pi ON pi.id=si.purchase_item_id WHERE si.shipment_id=sh.id AND pi.purchase_id=p.id)),'[]'::jsonb)
)::jsonb FROM app.purchases p WHERE p.id=sqlc.arg(id);
-- name: UpdateOpenShipmentDetails :exec
UPDATE app.shipments SET start_location=d->>'start_location',destination_warehouse_id=(d->>'destination_warehouse_id')::uuid,expected_arrival_at=nullif(d->>'expected_arrival_at','')::timestamptz,notes=nullif(d->>'notes','') FROM (SELECT sqlc.arg(data)::jsonb d) x WHERE id=sqlc.arg(id);
-- name: DeleteUnpaidShipmentStage :execrows
DELETE FROM app.transportation_stages WHERE id=sqlc.arg(id) AND shipment_id=sqlc.arg(shipment_id);
-- name: GetManagedWarehouse :one
SELECT to_jsonb(w)::jsonb FROM app.warehouses w WHERE id=$1 FOR UPDATE;
-- name: UpdateManagedWarehouse :exec
UPDATE app.warehouses SET name=d->>'name',address=nullif(d->>'address',''),is_active=(d->>'is_active')::boolean FROM (SELECT sqlc.arg(data)::jsonb d) x WHERE id=sqlc.arg(id);
-- name: ReverseUnallocatedPurchase :exec
SELECT app.reverse_unallocated_purchase(sqlc.arg(id)::uuid,sqlc.arg(actor)::uuid,sqlc.arg(reason)::text);
