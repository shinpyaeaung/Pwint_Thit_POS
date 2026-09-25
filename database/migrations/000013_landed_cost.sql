INSERT INTO app.permissions(code,description,is_sensitive) VALUES('costs.finalize','Finalize shipment landed costs and confirmed sellable quantities',true);
ALTER TABLE app.shipment_items ADD COLUMN purchase_cost_mmk numeric(20,4) CHECK(purchase_cost_mmk>=0 AND purchase_cost_mmk<>'NaN'::numeric);
ALTER TABLE app.shipment_items ADD COLUMN costing_sellable_quantity numeric(20,6) CHECK(costing_sellable_quantity>=0 AND costing_sellable_quantity<=expected_quantity AND costing_sellable_quantity<>'NaN'::numeric);
ALTER TABLE app.shipment_items ADD COLUMN landed_cost_mmk numeric(20,4) GENERATED ALWAYS AS (purchase_cost_mmk+allocated_transport_mmk+allocated_expense_mmk) STORED;
ALTER TABLE app.shipment_items ADD COLUMN actual_unit_cost_mmk numeric(24,8) GENERATED ALWAYS AS ((purchase_cost_mmk+allocated_transport_mmk+allocated_expense_mmk)/nullif(costing_sellable_quantity,0)) STORED;
ALTER TABLE app.shipment_items ADD CONSTRAINT costing_pair CHECK((purchase_cost_mmk IS NULL)=(costing_sellable_quantity IS NULL));
CREATE TABLE app.shipment_costings (
 shipment_id uuid PRIMARY KEY REFERENCES app.shipments(id),
 document jsonb NOT NULL CHECK(jsonb_typeof(document)='object'),
 finalized_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER shipment_costings_immutable BEFORE UPDATE OR DELETE ON app.shipment_costings FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
-- Cumulative rounding reconciles line MMK amounts to the immutable purchase total.
CREATE VIEW app.purchase_line_costs AS
 SELECT i.id,i.purchase_id,i.base_quantity,
 round(sum(i.total_original) OVER w*a.mmk_per_unit,4)-round((sum(i.total_original) OVER w-i.total_original)*a.mmk_per_unit,4) AS total_mmk
 FROM app.purchase_items i JOIN app.purchase_amounts a ON a.purchase_id=i.purchase_id
 WINDOW w AS (PARTITION BY i.purchase_id ORDER BY i.line_number ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);
