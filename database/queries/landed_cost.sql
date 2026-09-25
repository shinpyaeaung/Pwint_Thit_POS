-- name: LandedCostSources :one
SELECT jsonb_build_object('version',s.version::text,'status',s.status,'finalized',s.costs_finalized_at IS NOT NULL,
 'transport_mmk',(SELECT coalesce(sum(total_mmk),0)::text FROM app.transportation_stages WHERE shipment_id=s.id),
 'expense_mmk',(SELECT coalesce(sum(amount_mmk),0)::text FROM app.shipment_expenses WHERE shipment_id=s.id AND voided_at IS NULL),
 'items',coalesce((SELECT jsonb_agg(jsonb_build_object('id',si.id,'product_name',coalesce(pi.product_name_snapshot,pr.name),'sku',coalesce(pi.sku_snapshot,pr.sku),'base_unit_code',pr.base_unit_code,'expected_quantity',si.expected_quantity::text,'purchase_quantity',pi.base_quantity::text,'purchase_total_mmk',lc.total_mmk::text,
 'used_quantity',coalesce((SELECT sum(other.expected_quantity) FROM app.shipment_items other JOIN app.shipment_costings sc ON sc.shipment_id=other.shipment_id WHERE other.purchase_item_id=si.purchase_item_id AND other.id<>si.id),0)::text,
 'used_purchase_mmk',coalesce((SELECT sum(other.purchase_cost_mmk) FROM app.shipment_items other JOIN app.shipment_costings sc ON sc.shipment_id=other.shipment_id WHERE other.purchase_item_id=si.purchase_item_id AND other.id<>si.id),0)::text,
 'purchase_status',p.status) ORDER BY si.id) FROM app.shipment_items si JOIN app.purchase_items pi ON pi.id=si.purchase_item_id JOIN app.purchases p ON p.id=pi.purchase_id JOIN app.purchase_line_costs lc ON lc.id=pi.id JOIN app.products pr ON pr.id=si.product_id WHERE si.shipment_id=s.id),'[]'::jsonb))::jsonb FROM app.shipments s WHERE s.id=$1;
-- name: LockCostPurchaseItems :many
SELECT pi.id FROM app.purchase_items pi JOIN app.shipment_items si ON si.purchase_item_id=pi.id WHERE si.shipment_id=$1 ORDER BY pi.id FOR UPDATE OF pi;
-- name: GetFinalizedCost :one
SELECT document FROM app.shipment_costings WHERE shipment_id=$1;
-- name: SaveCostItem :exec
UPDATE app.shipment_items SET purchase_cost_mmk=(d->>'purchase_mmk')::numeric,costing_sellable_quantity=(d->>'sellable_quantity')::numeric,allocated_transport_mmk=(d->>'transport_mmk')::numeric,allocated_expense_mmk=(d->>'expense_mmk')::numeric,weight_kg=nullif(d->>'weight_kg','')::numeric,carton_quantity=nullif(d->>'carton_quantity','')::numeric FROM (SELECT sqlc.arg(data)::jsonb d) x WHERE id=(d->>'id')::uuid AND shipment_id=sqlc.arg(shipment_id);
-- name: SaveCostDocument :exec
INSERT INTO app.shipment_costings(shipment_id,document,finalized_by) VALUES($1,$2,$3);
-- name: FinalizeShipmentCost :exec
UPDATE app.shipments SET costs_finalized_at=now(),costs_finalized_by=$2,allocation_method=$3,version=version+1 WHERE id=$1;
