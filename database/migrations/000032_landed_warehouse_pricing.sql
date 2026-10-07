-- Finalized shipment allocations are immutable pricing references, not inventory revaluations.
CREATE VIEW app.warehouse_pricing_costs AS
 SELECT i.id AS shipment_item_id,i.product_id,s.destination_warehouse_id AS warehouse_id,
 s.id AS shipment_id,s.shipment_number,s.costs_finalized_at,p.purchase_number,
 i.purchase_cost_mmk,i.allocated_transport_mmk AS cargo_cost_mmk,
 i.allocated_expense_mmk AS additional_cost_mmk,i.landed_cost_mmk,
 i.costing_sellable_quantity AS sellable_quantity
 FROM app.shipment_items i JOIN app.shipments s ON s.id=i.shipment_id
 JOIN app.purchase_items pi ON pi.id=i.purchase_item_id JOIN app.purchases p ON p.id=pi.purchase_id
 WHERE s.costs_finalized_at IS NOT NULL AND s.status<>'CANCELLED' AND i.costing_sellable_quantity>0;

CREATE FUNCTION app.landed_warehouse_prices_save(d jsonb,actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE product app.products; source app.warehouse_pricing_costs; pack app.product_units;
 retail numeric; wholesale numeric; previous jsonb; saved jsonb;
BEGIN
 SELECT * INTO product FROM app.products WHERE id=(d->>'product_id')::uuid AND is_active AND archived_at IS NULL FOR UPDATE;
 IF NOT FOUND OR product.version::text<>d->>'version' THEN RAISE EXCEPTION 'pos: Product changed. Reopen pricing to refresh.' USING ERRCODE='23514'; END IF;
 PERFORM id FROM app.warehouses WHERE id=(d->>'warehouse_id')::uuid AND is_active FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'pos: Choose an active warehouse.' USING ERRCODE='23514'; END IF;
 SELECT * INTO source FROM app.warehouse_pricing_costs WHERE shipment_item_id=(d->>'shipment_item_id')::uuid AND product_id=product.id AND warehouse_id=(d->>'warehouse_id')::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'pos: Finalize landed costs for this product at this warehouse first.' USING ERRCODE='23514'; END IF;
 SELECT * INTO pack FROM app.product_units WHERE product_id=product.id AND unit_code=d->>'unit_code';
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM app.product_units WHERE product_id=product.id AND unit_code=product.base_unit_code AND units_per_pack=1) THEN RAISE EXCEPTION 'pos: Configure the product packaging and base unit first.' USING ERRCODE='23514'; END IF;
 retail=(d->>'retail_value')::numeric; wholesale=(d->>'wholesale_value')::numeric;
 IF retail IS NULL OR wholesale IS NULL OR retail<0 OR wholesale<0 OR retail='NaN' OR wholesale='NaN' THEN RAISE EXCEPTION 'pos: Enter valid positive prices or markup percentages.' USING ERRCODE='23514'; END IF;
 IF d->>'mode'='MARKUP' THEN
  -- Equivalent to marking up the carton landed cost, then dividing by its contents.
  retail=round(source.landed_cost_mmk/source.sellable_quantity*(1+retail/100),4);
  wholesale=round(source.landed_cost_mmk/source.sellable_quantity*(1+wholesale/100),4);
 ELSIF d->>'mode'='PER_UNIT' THEN
  retail=round(retail,4); wholesale=round(wholesale,4);
 ELSE RAISE EXCEPTION 'pos: Choose individual-unit pricing or markup.' USING ERRCODE='23514'; END IF;
 IF retail<=0 OR wholesale<=0 THEN RAISE EXCEPTION 'pos: Selling prices must be greater than zero.' USING ERRCODE='23514'; END IF;
 SELECT jsonb_agg(to_jsonb(wp)) INTO previous FROM app.warehouse_prices wp WHERE wp.product_id=product.id AND wp.warehouse_id=source.warehouse_id AND wp.unit_code IN (product.base_unit_code,pack.unit_code);
 INSERT INTO app.warehouse_prices(warehouse_id,product_id,unit_code,retail_price_mmk,wholesale_price_mmk)
 SELECT source.warehouse_id,product.id,u.unit_code,round(retail*u.units_per_pack,4),round(wholesale*u.units_per_pack,4)
 FROM app.product_units u WHERE u.product_id=product.id AND u.unit_code IN(product.base_unit_code,pack.unit_code)
 ON CONFLICT(warehouse_id,product_id,unit_code) DO UPDATE SET retail_price_mmk=excluded.retail_price_mmk,wholesale_price_mmk=excluded.wholesale_price_mmk;
 UPDATE app.products SET version=version+1 WHERE id=product.id;
 SELECT jsonb_agg(to_jsonb(wp)) INTO saved FROM app.warehouse_prices wp WHERE wp.product_id=product.id AND wp.warehouse_id=source.warehouse_id AND wp.unit_code IN(product.base_unit_code,pack.unit_code);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value)
 VALUES(actor,'warehouse_prices.landed_save','products',product.id,previous,jsonb_build_object('input',d,'cost_reference',to_jsonb(source),'prices',saved));
END $$;
