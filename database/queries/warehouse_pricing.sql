-- name: WarehousePricingCosts :one
SELECT coalesce(jsonb_agg(jsonb_build_object(
 'shipment_item_id',shipment_item_id,'shipment_number',shipment_number,'shipment_id',shipment_id,'purchase_number',purchase_number,
 'finalized_at',costs_finalized_at,'purchase_cost_mmk',purchase_cost_mmk::text,'cargo_cost_mmk',cargo_cost_mmk::text,
 'additional_cost_mmk',additional_cost_mmk::text,'landed_cost_mmk',landed_cost_mmk::text,'sellable_quantity',sellable_quantity::text
) ORDER BY costs_finalized_at DESC,shipment_item_id),'[]'::jsonb)::jsonb FROM app.warehouse_pricing_costs
WHERE product_id=sqlc.arg(product_id)::uuid AND warehouse_id=sqlc.arg(warehouse_id)::uuid;

-- name: LandedWarehousePricesSave :exec
SELECT app.landed_warehouse_prices_save(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid);
