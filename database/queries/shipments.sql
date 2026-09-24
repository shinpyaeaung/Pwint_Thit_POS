-- name: ShipmentWarehouses :one
SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) ORDER BY name),'[]'::jsonb)::jsonb FROM app.warehouses WHERE is_active;
-- name: CreateShipmentWarehouse :one
INSERT INTO app.warehouses(code,name,address) VALUES($1,$2,$3) RETURNING id;
-- name: LockShipmentWarehouse :one
SELECT id FROM app.warehouses WHERE id=$1 AND is_active FOR SHARE;
-- name: ShipmentPurchaseChoices :one
SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY purchase_number,line_number),'[]'::jsonb)::jsonb FROM (
 SELECT i.id,p.purchase_number,i.line_number,p.supplier_id,s.name AS supplier_name,COALESCE(i.product_name_snapshot,pr.name) AS product_name,COALESCE(i.sku_snapshot,pr.sku) AS sku,i.unit_code,i.quantity::text AS purchased_quantity,i.base_quantity::text AS base_quantity,
 (i.base_quantity-COALESCE((SELECT sum(si.expected_quantity) FROM app.shipment_items si JOIN app.shipments sh ON sh.id=si.shipment_id WHERE si.purchase_item_id=i.id AND sh.status<>'CANCELLED'),0))::text AS available_quantity
 FROM app.purchase_items i JOIN app.purchases p ON p.id=i.purchase_id JOIN app.suppliers s ON s.id=p.supplier_id JOIN app.products pr ON pr.id=i.product_id
 WHERE p.status='POSTED' AND (sqlc.arg(search)::text='' OR strpos(lower(p.purchase_number||' '||s.name||' '||pr.name),lower(sqlc.arg(search)))>0)
 ORDER BY p.purchased_at DESC,i.line_number LIMIT 50) x;
-- name: LockShipmentPurchaseItem :one
SELECT i.product_id,i.base_quantity::text AS base_quantity FROM app.purchase_items i JOIN app.purchases p ON p.id=i.purchase_id WHERE i.id=$1 AND p.status='POSTED' FOR UPDATE OF i;
-- name: ShipmentReservedQuantity :one
SELECT COALESCE(sum(i.expected_quantity),0)::text FROM app.shipment_items i JOIN app.shipments s ON s.id=i.shipment_id WHERE i.purchase_item_id=$1 AND s.status<>'CANCELLED';
-- name: InsertShipment :one
INSERT INTO app.shipments(shipment_number,start_location,destination_warehouse_id,expected_arrival_at,created_by,notes,request_id)
SELECT d->>'shipment_number',d->>'start_location',(d->>'destination_warehouse_id')::uuid,NULLIF(d->>'expected_arrival_at','')::timestamptz,sqlc.arg(actor),NULLIF(d->>'notes',''),(d->>'request_id')::uuid FROM (SELECT sqlc.arg(data)::jsonb d) x RETURNING id;
-- name: InsertShipmentItem :exec
INSERT INTO app.shipment_items(shipment_id,purchase_item_id,product_id,expected_quantity) VALUES($1,$2,$3,$4);
-- name: LockShipment :one
SELECT id,status,version,costs_finalized_at,shipped_at FROM app.shipments WHERE id=$1 FOR UPDATE;
-- name: TouchShipment :exec
UPDATE app.shipments SET version=version+1 WHERE id=$1;
-- name: GetShipment :one
SELECT app.shipment_document(s,sqlc.arg(costs)::boolean)::jsonb FROM app.shipments s WHERE id=sqlc.arg(id);
-- name: ListShipments :one
WITH filtered AS (SELECT * FROM app.shipments WHERE (sqlc.arg(search)::text='' OR strpos(lower(shipment_number||' '||start_location),lower(sqlc.arg(search)))>0) AND (sqlc.arg(status)::text='' OR status=sqlc.arg(status))), page AS (SELECT id FROM filtered ORDER BY created_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'shipments',COALESCE((SELECT jsonb_agg(app.shipment_document(s,sqlc.arg(costs)::boolean) ORDER BY s.created_at DESC,s.id) FROM app.shipments s JOIN page USING(id)),'[]'::jsonb))::jsonb;
-- name: ShipmentItems :one
SELECT COALESCE(jsonb_agg(jsonb_build_object('id',si.id,'purchase_number',p.purchase_number,'supplier_name',s.name,'product_name',COALESCE(i.product_name_snapshot,pr.name),'sku',COALESCE(i.sku_snapshot,pr.sku),'expected_quantity',si.expected_quantity::text,'base_unit_code',pr.base_unit_code) ORDER BY p.purchase_number,i.line_number),'[]'::jsonb)::jsonb FROM app.shipment_items si JOIN app.purchase_items i ON i.id=si.purchase_item_id JOIN app.purchases p ON p.id=i.purchase_id JOIN app.suppliers s ON s.id=p.supplier_id JOIN app.products pr ON pr.id=i.product_id WHERE si.shipment_id=$1;
-- name: ShipmentHasReceiving :one
SELECT EXISTS(SELECT 1 FROM app.goods_receiving WHERE shipment_id=$1 AND status NOT IN ('CANCELLED','REVERSED'))::boolean;
-- name: UpdateShipmentStatus :exec
UPDATE app.shipments SET status=sqlc.arg(status),shipped_at=COALESCE(shipped_at,sqlc.narg(shipped_at)::timestamptz),arrived_at=sqlc.narg(arrived_at)::timestamptz WHERE id=sqlc.arg(id);
-- name: ShipmentStages :one
SELECT jsonb_build_object('total',(SELECT count(*) FROM app.transportation_stages cnt WHERE cnt.shipment_id=sqlc.arg(shipment_id)),'stages',COALESCE((SELECT jsonb_agg(app.stage_document(t,sqlc.arg(costs)::boolean) ORDER BY t.stage_number) FROM app.transportation_stages t JOIN (SELECT z.id FROM app.transportation_stages z WHERE z.shipment_id=sqlc.arg(shipment_id) ORDER BY z.stage_number LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int) page USING(id)),'[]'::jsonb))::jsonb;
-- name: InsertShipmentStage :one
INSERT INTO app.transportation_stages(shipment_id,stage_number,start_location,destination,provider_name,transportation_type,vehicle_information,departed_at,arrived_at,transportation_fee_mmk,loading_fee_mmk,unloading_fee_mmk,other_fee_mmk,notes,request_id)
SELECT sqlc.arg(shipment_id),(SELECT COALESCE(max(stage_number),0)+1 FROM app.transportation_stages WHERE shipment_id=sqlc.arg(shipment_id)),d->>'start_location',d->>'destination',d->>'provider_name',NULLIF(d->>'transportation_type',''),NULLIF(d->>'vehicle_information',''),NULLIF(d->>'departed_at','')::timestamptz,NULLIF(d->>'arrived_at','')::timestamptz,(d->>'transportation_fee_mmk')::numeric,(d->>'loading_fee_mmk')::numeric,(d->>'unloading_fee_mmk')::numeric,(d->>'other_fee_mmk')::numeric,NULLIF(d->>'notes',''),(d->>'request_id')::uuid FROM (SELECT sqlc.arg(data)::jsonb d) x RETURNING id;
-- name: UpdateShipmentStage :execrows
UPDATE app.transportation_stages SET start_location=d->>'start_location',destination=d->>'destination',provider_name=d->>'provider_name',transportation_type=NULLIF(d->>'transportation_type',''),vehicle_information=NULLIF(d->>'vehicle_information',''),departed_at=NULLIF(d->>'departed_at','')::timestamptz,arrived_at=NULLIF(d->>'arrived_at','')::timestamptz,transportation_fee_mmk=(d->>'transportation_fee_mmk')::numeric,loading_fee_mmk=(d->>'loading_fee_mmk')::numeric,unloading_fee_mmk=(d->>'unloading_fee_mmk')::numeric,other_fee_mmk=(d->>'other_fee_mmk')::numeric,notes=NULLIF(d->>'notes','') FROM (SELECT sqlc.arg(data)::jsonb d) x WHERE id=sqlc.arg(id) AND shipment_id=sqlc.arg(shipment_id);
-- name: ShipmentChildHasPayment :one
SELECT EXISTS(SELECT 1 FROM app.payment_allocations WHERE transportation_stage_id=$1 OR shipment_expense_id=$1)::boolean;
-- name: GetShipmentStage :one
SELECT app.stage_document(t,true)::jsonb FROM app.transportation_stages t WHERE id=$1 AND shipment_id=$2 FOR UPDATE;
-- name: ShipmentExpenses :one
SELECT jsonb_build_object('total',(SELECT count(*) FROM app.shipment_expenses cnt WHERE cnt.shipment_id=sqlc.arg(shipment_id)),'expenses',COALESCE((SELECT jsonb_agg(app.shipment_expense_document(e,sqlc.arg(costs)::boolean) ORDER BY e.created_at,e.id) FROM app.shipment_expenses e JOIN (SELECT z.id FROM app.shipment_expenses z WHERE z.shipment_id=sqlc.arg(shipment_id) ORDER BY z.created_at,z.id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int) page USING(id)),'[]'::jsonb))::jsonb;
-- name: InsertShipmentExpense :one
INSERT INTO app.shipment_expenses(shipment_id,category,description,currency_code,amount_original,mmk_per_unit,incurred_at,recorded_by,notes,request_id)
SELECT sqlc.arg(shipment_id),d->>'category',d->>'description',d->>'currency_code',(d->>'amount_original')::numeric,(d->>'mmk_per_unit')::numeric,(d->>'incurred_at')::timestamptz,sqlc.arg(actor),NULLIF(d->>'notes',''),(d->>'request_id')::uuid FROM (SELECT sqlc.arg(data)::jsonb d) x RETURNING id;
-- name: GetShipmentExpense :one
SELECT app.shipment_expense_document(e,true)::jsonb FROM app.shipment_expenses e WHERE id=$1 AND shipment_id=$2 FOR UPDATE;
-- name: VoidShipmentExpense :execrows
UPDATE app.shipment_expenses SET voided_at=clock_timestamp(),void_reason=sqlc.arg(reason) WHERE id=sqlc.arg(id) AND shipment_id=sqlc.arg(shipment_id) AND voided_at IS NULL;
