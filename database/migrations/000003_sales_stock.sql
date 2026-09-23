CREATE TABLE app.sales (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), invoice_number text NOT NULL UNIQUE,
 customer_id uuid REFERENCES app.customers(id), warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 pricing_mode text NOT NULL CHECK(pricing_mode IN ('RETAIL','WHOLESALE')),
 sold_at timestamptz NOT NULL, due_date date,
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')),
 posted_at timestamptz, created_by uuid NOT NULL REFERENCES app.users(id), notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((status IN ('POSTED','REVERSED'))=(posted_at IS NOT NULL)),
 CHECK(due_date IS NULL OR customer_id IS NOT NULL), UNIQUE(id,customer_id)
);
CREATE TABLE app.sale_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sale_id uuid NOT NULL REFERENCES app.sales(id),
 line_number integer NOT NULL CHECK(line_number>0), product_id uuid NOT NULL REFERENCES app.products(id),
 unit_code text NOT NULL REFERENCES app.units(code), units_per_pack numeric(20,6) NOT NULL CHECK(units_per_pack>0),
 quantity numeric(20,6) NOT NULL CHECK(quantity>0),
 base_quantity numeric(20,6) GENERATED ALWAYS AS (quantity*units_per_pack) STORED,
 unit_price_mmk numeric(20,6) NOT NULL CHECK(unit_price_mmk>=0),
 discount_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(discount_mmk>=0),
 tax_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(tax_mmk>=0),
 total_mmk numeric(20,4) GENERATED ALWAYS AS (round(quantity*unit_price_mmk-discount_mmk+tax_mmk,4)) STORED,
 price_reason text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(discount_mmk<=quantity*unit_price_mmk), UNIQUE(sale_id,line_number), UNIQUE(id,product_id), UNIQUE(id,sale_id,product_id)
);
CREATE TABLE app.sale_item_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sale_item_id uuid NOT NULL, batch_id uuid NOT NULL,
 product_id uuid NOT NULL REFERENCES app.products(id), quantity numeric(20,6) NOT NULL CHECK(quantity>0),
 unit_cost_mmk numeric(24,8) NOT NULL CHECK(unit_cost_mmk>=0),
 total_cost_mmk numeric(20,4) GENERATED ALWAYS AS (round(quantity*unit_cost_mmk,4)) STORED,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(sale_item_id,product_id) REFERENCES app.sale_items(id,product_id),
 FOREIGN KEY(batch_id,product_id) REFERENCES app.batches(id,product_id),
 UNIQUE(sale_item_id,batch_id), UNIQUE(id,sale_item_id,product_id), UNIQUE(id,batch_id,product_id)
);
CREATE TABLE app.sales_returns (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), return_number text NOT NULL UNIQUE, sale_id uuid NOT NULL REFERENCES app.sales(id),
 return_type text NOT NULL CHECK(return_type IN ('REFUND','EXCHANGE','CREDIT')),
 replacement_sale_id uuid REFERENCES app.sales(id), returned_at timestamptz NOT NULL,
 reason text NOT NULL CHECK(btrim(reason)<>''),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')),
 posted_at timestamptz, created_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((status IN ('POSTED','REVERSED'))=(posted_at IS NOT NULL)),
 CHECK(replacement_sale_id IS NULL OR (return_type='EXCHANGE' AND replacement_sale_id<>sale_id)), UNIQUE(id,sale_id)
);
CREATE TABLE app.sales_return_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sales_return_id uuid NOT NULL, sale_id uuid NOT NULL,
 sale_item_id uuid NOT NULL, sale_item_batch_id uuid NOT NULL, product_id uuid NOT NULL REFERENCES app.products(id),
 quantity numeric(20,6) NOT NULL CHECK(quantity>0), refund_mmk numeric(20,4) NOT NULL CHECK(refund_mmk>=0),
 disposition text NOT NULL CHECK(disposition IN ('SELLABLE','DAMAGED','DISCARD')),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(sales_return_id,sale_id) REFERENCES app.sales_returns(id,sale_id),
 FOREIGN KEY(sale_item_id,sale_id,product_id) REFERENCES app.sale_items(id,sale_id,product_id),
 FOREIGN KEY(sale_item_batch_id,sale_item_id,product_id) REFERENCES app.sale_item_batches(id,sale_item_id,product_id)
);
CREATE TABLE app.purchase_returns (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), return_number text NOT NULL UNIQUE,
 purchase_id uuid NOT NULL REFERENCES app.purchases(id), returned_at timestamptz NOT NULL,
 resolution text NOT NULL CHECK(resolution IN ('REFUND','SUPPLIER_CREDIT')),
 reason text NOT NULL CHECK(btrim(reason)<>''),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')),
 posted_at timestamptz, created_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((status IN ('POSTED','REVERSED'))=(posted_at IS NOT NULL)), UNIQUE(id,purchase_id)
);
ALTER TABLE app.purchase_items ADD UNIQUE(id,purchase_id,product_id);
CREATE TABLE app.purchase_return_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), purchase_return_id uuid NOT NULL, purchase_id uuid NOT NULL,
 purchase_item_id uuid NOT NULL, product_id uuid NOT NULL REFERENCES app.products(id), batch_id uuid,
 quantity numeric(20,6) NOT NULL CHECK(quantity>0),
 credit_original numeric(20,4) NOT NULL CHECK(credit_original>=0),
 credit_mmk numeric(20,4) NOT NULL CHECK(credit_mmk>=0),
 inventory_cost_mmk numeric(20,4) NOT NULL CHECK(inventory_cost_mmk>=0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(purchase_return_id,purchase_id) REFERENCES app.purchase_returns(id,purchase_id),
 FOREIGN KEY(purchase_item_id,purchase_id,product_id) REFERENCES app.purchase_items(id,purchase_id,product_id),
 FOREIGN KEY(batch_id,product_id) REFERENCES app.batches(id,product_id)
);
CREATE TABLE app.stock_adjustments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 reason text NOT NULL CHECK(btrim(reason)<>''), adjusted_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')),
 posted_at timestamptz, created_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((status IN ('POSTED','REVERSED'))=(posted_at IS NOT NULL))
);
CREATE TABLE app.stock_adjustment_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stock_adjustment_id uuid NOT NULL REFERENCES app.stock_adjustments(id),
 batch_id uuid NOT NULL REFERENCES app.batches(id), quantity_delta numeric(20,6) NOT NULL CHECK(quantity_delta<>0),
 stock_bucket text NOT NULL CHECK(stock_bucket IN ('SELLABLE','DAMAGED','RESERVED')),
 unit_cost_mmk numeric(24,8) NOT NULL CHECK(unit_cost_mmk>=0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.stock_transfers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), transfer_number text NOT NULL UNIQUE,
 from_warehouse_id uuid NOT NULL REFERENCES app.warehouses(id), to_warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','IN_TRANSIT','RECEIVED','CANCELLED','REVERSED')),
 dispatched_at timestamptz, received_at timestamptz, created_by uuid NOT NULL REFERENCES app.users(id), notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(from_warehouse_id<>to_warehouse_id), CHECK(received_at IS NULL OR (dispatched_at IS NOT NULL AND received_at>=dispatched_at))
);
CREATE TABLE app.stock_transfer_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), transfer_id uuid NOT NULL REFERENCES app.stock_transfers(id),
 batch_id uuid NOT NULL REFERENCES app.batches(id), quantity numeric(20,6) NOT NULL CHECK(quantity>0),
 received_quantity numeric(20,6) CHECK(received_quantity>=0 AND received_quantity<=quantity),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(transfer_id,batch_id)
);
CREATE TABLE app.stock_takes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 counted_at timestamptz NOT NULL, counted_by uuid NOT NULL REFERENCES app.users(id),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','SUBMITTED','APPROVED','CANCELLED')),
 adjustment_id uuid UNIQUE REFERENCES app.stock_adjustments(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.stock_take_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stock_take_id uuid NOT NULL REFERENCES app.stock_takes(id), batch_id uuid NOT NULL REFERENCES app.batches(id),
 stock_bucket text NOT NULL CHECK(stock_bucket IN ('SELLABLE','DAMAGED','RESERVED')),
 system_quantity numeric(20,6) NOT NULL CHECK(system_quantity>=0), counted_quantity numeric(20,6) NOT NULL CHECK(counted_quantity>=0),
 difference numeric(20,6) GENERATED ALWAYS AS(counted_quantity-system_quantity) STORED,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(stock_take_id,batch_id,stock_bucket)
);
CREATE TABLE app.damaged_products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES app.products(id), batch_id uuid,
 shipment_item_id uuid, warehouse_id uuid REFERENCES app.warehouses(id),
 quantity numeric(20,6) NOT NULL CHECK(quantity>0), estimated_loss_mmk numeric(20,4) NOT NULL CHECK(estimated_loss_mmk>=0),
 reason text NOT NULL CHECK(btrim(reason)<>''), occurred_at timestamptz NOT NULL, recorded_by uuid NOT NULL REFERENCES app.users(id),
 disposition text NOT NULL CHECK(disposition IN ('QUARANTINE','DISCARD','REDUCED_PRICE','RETURN_TO_SUPPLIER')),
 original_price_mmk numeric(20,4) CHECK(original_price_mmk>=0), reduced_price_mmk numeric(20,4) CHECK(reduced_price_mmk>=0),
 notes text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(batch_id,product_id) REFERENCES app.batches(id,product_id),
 FOREIGN KEY(shipment_item_id,product_id) REFERENCES app.shipment_items(id,product_id),
 CHECK(batch_id IS NOT NULL OR shipment_item_id IS NOT NULL),
 CHECK(disposition<>'REDUCED_PRICE' OR (original_price_mmk IS NOT NULL AND reduced_price_mmk IS NOT NULL AND reduced_price_mmk<=original_price_mmk))
);
CREATE TABLE app.missing_products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES app.products(id), batch_id uuid,
 shipment_item_id uuid, warehouse_id uuid REFERENCES app.warehouses(id),
 quantity numeric(20,6) NOT NULL CHECK(quantity>0), estimated_loss_mmk numeric(20,4) NOT NULL CHECK(estimated_loss_mmk>=0),
 reason text NOT NULL CHECK(btrim(reason)<>''), occurred_at timestamptz NOT NULL, recorded_by uuid NOT NULL REFERENCES app.users(id), notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(batch_id,product_id) REFERENCES app.batches(id,product_id),
 FOREIGN KEY(shipment_item_id,product_id) REFERENCES app.shipment_items(id,product_id),
 CHECK(batch_id IS NOT NULL OR shipment_item_id IS NOT NULL)
);
CREATE TABLE app.inventory (
 warehouse_id uuid NOT NULL REFERENCES app.warehouses(id), batch_id uuid NOT NULL REFERENCES app.batches(id),
 sellable_quantity numeric(20,6) NOT NULL DEFAULT 0 CHECK(sellable_quantity>=0),
 reserved_quantity numeric(20,6) NOT NULL DEFAULT 0 CHECK(reserved_quantity>=0),
 damaged_quantity numeric(20,6) NOT NULL DEFAULT 0 CHECK(damaged_quantity>=0),
 available_quantity numeric(20,6) GENERATED ALWAYS AS (sellable_quantity-reserved_quantity) STORED,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(reserved_quantity<=sellable_quantity), PRIMARY KEY(warehouse_id,batch_id)
);
CREATE TABLE app.inventory_movements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), warehouse_id uuid NOT NULL REFERENCES app.warehouses(id), batch_id uuid NOT NULL REFERENCES app.batches(id),
 movement_type text NOT NULL CHECK(movement_type IN ('RECEIPT','SALE','SALE_RETURN','PURCHASE_RETURN','DAMAGE','MISSING','ADJUSTMENT','TRANSFER','RESERVATION','REVERSAL')),
 sellable_delta numeric(20,6) NOT NULL DEFAULT 0, reserved_delta numeric(20,6) NOT NULL DEFAULT 0, damaged_delta numeric(20,6) NOT NULL DEFAULT 0,
 unit_cost_mmk numeric(24,8) NOT NULL CHECK(unit_cost_mmk>=0),
 receiving_item_id uuid REFERENCES app.goods_receiving_items(id), sale_item_batch_id uuid REFERENCES app.sale_item_batches(id),
 sales_return_item_id uuid REFERENCES app.sales_return_items(id), purchase_return_item_id uuid REFERENCES app.purchase_return_items(id),
 stock_adjustment_item_id uuid REFERENCES app.stock_adjustment_items(id), stock_transfer_item_id uuid REFERENCES app.stock_transfer_items(id),
 damaged_product_id uuid REFERENCES app.damaged_products(id), missing_product_id uuid REFERENCES app.missing_products(id),
 reservation_sale_id uuid REFERENCES app.sales(id), reverses_movement_id uuid UNIQUE REFERENCES app.inventory_movements(id),
 idempotency_key text NOT NULL UNIQUE, occurred_at timestamptz NOT NULL,
 recorded_by uuid NOT NULL REFERENCES app.users(id), reason text,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(sellable_delta<>0 OR reserved_delta<>0 OR damaged_delta<>0),
 CHECK(num_nonnulls(receiving_item_id,sale_item_batch_id,sales_return_item_id,purchase_return_item_id,stock_adjustment_item_id,stock_transfer_item_id,damaged_product_id,missing_product_id,reservation_sale_id,reverses_movement_id)=1),
 CHECK((movement_type='REVERSAL')=(reverses_movement_id IS NOT NULL)),
 CHECK((movement_type='RECEIPT')=(receiving_item_id IS NOT NULL)),
 CHECK((movement_type='SALE')=(sale_item_batch_id IS NOT NULL)),
 CHECK((movement_type='SALE_RETURN')=(sales_return_item_id IS NOT NULL)),
 CHECK((movement_type='PURCHASE_RETURN')=(purchase_return_item_id IS NOT NULL)),
 CHECK((movement_type='ADJUSTMENT')=(stock_adjustment_item_id IS NOT NULL)),
 CHECK((movement_type='TRANSFER')=(stock_transfer_item_id IS NOT NULL)),
 CHECK((movement_type='DAMAGE')=(damaged_product_id IS NOT NULL)),
 CHECK((movement_type='MISSING')=(missing_product_id IS NOT NULL)),
 CHECK((movement_type='RESERVATION')=(reservation_sale_id IS NOT NULL))
);
CREATE INDEX inventory_movements_history ON app.inventory_movements(warehouse_id,batch_id,occurred_at,id);

ALTER TABLE app.sale_items ADD CONSTRAINT sale_items_finite_numbers CHECK (units_per_pack <> 'NaN'::numeric AND quantity <> 'NaN'::numeric AND base_quantity <> 'NaN'::numeric AND unit_price_mmk <> 'NaN'::numeric AND discount_mmk <> 'NaN'::numeric AND tax_mmk <> 'NaN'::numeric AND total_mmk <> 'NaN'::numeric);

ALTER TABLE app.sale_item_batches ADD CONSTRAINT sale_item_batches_finite_numbers CHECK (quantity <> 'NaN'::numeric AND unit_cost_mmk <> 'NaN'::numeric AND total_cost_mmk <> 'NaN'::numeric);

ALTER TABLE app.sales_return_items ADD CONSTRAINT sales_return_items_finite_numbers CHECK (quantity <> 'NaN'::numeric AND refund_mmk <> 'NaN'::numeric);

ALTER TABLE app.purchase_return_items ADD CONSTRAINT purchase_return_items_finite_numbers CHECK (quantity <> 'NaN'::numeric AND credit_original <> 'NaN'::numeric AND credit_mmk <> 'NaN'::numeric AND inventory_cost_mmk <> 'NaN'::numeric);

ALTER TABLE app.stock_adjustment_items ADD CONSTRAINT stock_adjustment_items_finite_numbers CHECK (quantity_delta <> 'NaN'::numeric AND unit_cost_mmk <> 'NaN'::numeric);

ALTER TABLE app.stock_transfer_items ADD CONSTRAINT stock_transfer_items_finite_numbers CHECK (quantity <> 'NaN'::numeric AND received_quantity <> 'NaN'::numeric);

ALTER TABLE app.stock_take_items ADD CONSTRAINT stock_take_items_finite_numbers CHECK (system_quantity <> 'NaN'::numeric AND counted_quantity <> 'NaN'::numeric AND difference <> 'NaN'::numeric);

ALTER TABLE app.damaged_products ADD CONSTRAINT damaged_products_finite_numbers CHECK (quantity <> 'NaN'::numeric AND estimated_loss_mmk <> 'NaN'::numeric AND original_price_mmk <> 'NaN'::numeric AND reduced_price_mmk <> 'NaN'::numeric);

ALTER TABLE app.missing_products ADD CONSTRAINT missing_products_finite_numbers CHECK (quantity <> 'NaN'::numeric AND estimated_loss_mmk <> 'NaN'::numeric);

ALTER TABLE app.inventory ADD CONSTRAINT inventory_finite_numbers CHECK (sellable_quantity <> 'NaN'::numeric AND reserved_quantity <> 'NaN'::numeric AND damaged_quantity <> 'NaN'::numeric AND available_quantity <> 'NaN'::numeric);

ALTER TABLE app.inventory_movements ADD CONSTRAINT inventory_movements_finite_numbers CHECK (sellable_delta <> 'NaN'::numeric AND reserved_delta <> 'NaN'::numeric AND damaged_delta <> 'NaN'::numeric AND unit_cost_mmk <> 'NaN'::numeric);
