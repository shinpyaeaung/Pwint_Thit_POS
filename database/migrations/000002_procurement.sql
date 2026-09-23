CREATE TABLE app.purchases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), purchase_number text NOT NULL UNIQUE,
 supplier_id uuid NOT NULL REFERENCES app.suppliers(id), supplier_invoice_number text,
 purchased_at timestamptz NOT NULL, due_date date,
 currency_code text NOT NULL REFERENCES app.currencies(code),
 exchange_rate_id uuid REFERENCES app.exchange_rates(id),
 mmk_per_unit numeric(24,10) NOT NULL CHECK(mmk_per_unit>0),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')),
 posted_at timestamptz, created_by uuid NOT NULL REFERENCES app.users(id),
 notes text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(currency_code<>'MMK' OR mmk_per_unit=1),
 CHECK((status IN ('POSTED','REVERSED')) = (posted_at IS NOT NULL)),
 UNIQUE(id,supplier_id)
);
CREATE UNIQUE INDEX purchases_supplier_invoice ON app.purchases(supplier_id,supplier_invoice_number) WHERE supplier_invoice_number IS NOT NULL;
CREATE TABLE app.purchase_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), purchase_id uuid NOT NULL REFERENCES app.purchases(id),
 line_number integer NOT NULL CHECK(line_number>0), product_id uuid NOT NULL REFERENCES app.products(id),
 unit_code text NOT NULL REFERENCES app.units(code), quantity numeric(20,6) NOT NULL CHECK(quantity>0),
 units_per_pack numeric(20,6) NOT NULL CHECK(units_per_pack>0),
 base_quantity numeric(20,6) GENERATED ALWAYS AS (quantity*units_per_pack) STORED,
 unit_price_original numeric(20,6) NOT NULL CHECK(unit_price_original>=0),
 discount_original numeric(20,4) NOT NULL DEFAULT 0 CHECK(discount_original>=0),
 tax_original numeric(20,4) NOT NULL DEFAULT 0 CHECK(tax_original>=0),
 total_original numeric(20,4) GENERATED ALWAYS AS (round(quantity*unit_price_original-discount_original+tax_original,4)) STORED,
 notes text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(discount_original<=quantity*unit_price_original),
 UNIQUE(purchase_id,line_number), UNIQUE(id,product_id)
);
CREATE TABLE app.shipments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shipment_number text NOT NULL UNIQUE,
 start_location text NOT NULL, destination_warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 shipped_at timestamptz, expected_arrival_at timestamptz, arrived_at timestamptz,
 status text NOT NULL DEFAULT 'PREPARING' CHECK(status IN ('PREPARING','IN_TRANSIT','ARRIVED','RECEIVED','CANCELLED')),
 allocation_method text NOT NULL DEFAULT 'PURCHASE_VALUE' CHECK(allocation_method IN ('QUANTITY','PURCHASE_VALUE','WEIGHT','CARTONS','MANUAL')),
 costs_finalized_at timestamptz, costs_finalized_by uuid REFERENCES app.users(id),
 created_by uuid NOT NULL REFERENCES app.users(id), notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((costs_finalized_at IS NULL)=(costs_finalized_by IS NULL)),
 CHECK(arrived_at IS NULL OR shipped_at IS NULL OR arrived_at>=shipped_at)
);
CREATE TABLE app.shipment_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shipment_id uuid NOT NULL REFERENCES app.shipments(id),
 purchase_item_id uuid NOT NULL, product_id uuid NOT NULL REFERENCES app.products(id),
 expected_quantity numeric(20,6) NOT NULL CHECK(expected_quantity>0),
 weight_kg numeric(20,6) CHECK(weight_kg>0), carton_quantity numeric(20,6) CHECK(carton_quantity>=0),
 allocated_transport_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(allocated_transport_mmk>=0),
 allocated_expense_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(allocated_expense_mmk>=0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(purchase_item_id,product_id) REFERENCES app.purchase_items(id,product_id),
 UNIQUE(shipment_id,purchase_item_id), UNIQUE(id,shipment_id,product_id), UNIQUE(id,product_id)
);
CREATE TABLE app.transportation_stages (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shipment_id uuid NOT NULL REFERENCES app.shipments(id),
 stage_number integer NOT NULL CHECK(stage_number>0), start_location text NOT NULL, destination text NOT NULL,
 provider_name text NOT NULL, transportation_type text, vehicle_information text,
 departed_at timestamptz, arrived_at timestamptz,
 transportation_fee_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(transportation_fee_mmk>=0),
 loading_fee_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(loading_fee_mmk>=0),
 unloading_fee_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(unloading_fee_mmk>=0),
 other_fee_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(other_fee_mmk>=0),
 total_mmk numeric(20,4) GENERATED ALWAYS AS (transportation_fee_mmk+loading_fee_mmk+unloading_fee_mmk+other_fee_mmk) STORED,
 notes text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(shipment_id,stage_number), CHECK(arrived_at IS NULL OR departed_at IS NULL OR arrived_at>=departed_at)
);
CREATE TABLE app.shipment_expenses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shipment_id uuid NOT NULL REFERENCES app.shipments(id),
 category text NOT NULL, description text NOT NULL,
 currency_code text NOT NULL REFERENCES app.currencies(code),
 amount_original numeric(20,4) NOT NULL CHECK(amount_original>0),
 mmk_per_unit numeric(24,10) NOT NULL CHECK(mmk_per_unit>0),
 amount_mmk numeric(20,4) GENERATED ALWAYS AS (round(amount_original*mmk_per_unit,4)) STORED,
 incurred_at timestamptz NOT NULL, recorded_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(currency_code<>'MMK' OR mmk_per_unit=1)
);
CREATE TABLE app.goods_receiving (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), receipt_number text NOT NULL UNIQUE,
 shipment_id uuid NOT NULL REFERENCES app.shipments(id), warehouse_id uuid NOT NULL REFERENCES app.warehouses(id),
 received_at timestamptz NOT NULL, received_by uuid NOT NULL REFERENCES app.users(id),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')),
 posted_at timestamptz, notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK((status IN ('POSTED','REVERSED'))=(posted_at IS NOT NULL)), UNIQUE(id,shipment_id)
);
CREATE TABLE app.goods_receiving_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), goods_receiving_id uuid NOT NULL, shipment_id uuid NOT NULL,
 shipment_item_id uuid NOT NULL, product_id uuid NOT NULL REFERENCES app.products(id),
 expected_quantity numeric(20,6) NOT NULL CHECK(expected_quantity>0),
 received_quantity numeric(20,6) NOT NULL CHECK(received_quantity>=0),
 damaged_quantity numeric(20,6) NOT NULL DEFAULT 0 CHECK(damaged_quantity>=0),
 missing_quantity numeric(20,6) GENERATED ALWAYS AS (greatest(expected_quantity-received_quantity,0)) STORED,
 excess_quantity numeric(20,6) GENERATED ALWAYS AS (greatest(received_quantity-expected_quantity,0)) STORED,
 batch_number text NOT NULL, manufactured_on date, expires_on date, notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(damaged_quantity<=received_quantity), CHECK(expires_on IS NULL OR manufactured_on IS NULL OR expires_on>=manufactured_on),
 FOREIGN KEY(goods_receiving_id,shipment_id) REFERENCES app.goods_receiving(id,shipment_id),
 FOREIGN KEY(shipment_item_id,shipment_id,product_id) REFERENCES app.shipment_items(id,shipment_id,product_id),
 UNIQUE(id,product_id)
);
CREATE TABLE app.batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES app.products(id),
 receiving_item_id uuid NOT NULL UNIQUE,
 batch_number text NOT NULL, received_at timestamptz NOT NULL, manufactured_on date, expires_on date,
 purchase_cost_mmk numeric(20,4) NOT NULL CHECK(purchase_cost_mmk>=0),
 transport_cost_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(transport_cost_mmk>=0),
 other_cost_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK(other_cost_mmk>=0),
 sellable_quantity numeric(20,6) NOT NULL CHECK(sellable_quantity>=0),
 total_cost_mmk numeric(20,4) GENERATED ALWAYS AS (purchase_cost_mmk+transport_cost_mmk+other_cost_mmk) STORED,
 actual_unit_cost_mmk numeric(24,8) GENERATED ALWAYS AS ((purchase_cost_mmk+transport_cost_mmk+other_cost_mmk)/nullif(sellable_quantity,0)) STORED,
 finalized_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(receiving_item_id,product_id) REFERENCES app.goods_receiving_items(id,product_id),
 CHECK(expires_on IS NULL OR manufactured_on IS NULL OR expires_on>=manufactured_on), UNIQUE(id,product_id)
);
CREATE INDEX batches_fifo ON app.batches(product_id,received_at,id);
CREATE INDEX batches_expiry ON app.batches(expires_on) WHERE expires_on IS NOT NULL;

ALTER TABLE app.purchases ADD CONSTRAINT purchases_finite_numbers CHECK (mmk_per_unit <> 'NaN'::numeric);

ALTER TABLE app.purchase_items ADD CONSTRAINT purchase_items_finite_numbers CHECK (quantity <> 'NaN'::numeric AND units_per_pack <> 'NaN'::numeric AND base_quantity <> 'NaN'::numeric AND unit_price_original <> 'NaN'::numeric AND discount_original <> 'NaN'::numeric AND tax_original <> 'NaN'::numeric AND total_original <> 'NaN'::numeric);

ALTER TABLE app.shipment_items ADD CONSTRAINT shipment_items_finite_numbers CHECK (expected_quantity <> 'NaN'::numeric AND weight_kg <> 'NaN'::numeric AND carton_quantity <> 'NaN'::numeric AND allocated_transport_mmk <> 'NaN'::numeric AND allocated_expense_mmk <> 'NaN'::numeric);

ALTER TABLE app.transportation_stages ADD CONSTRAINT transportation_stages_finite_numbers CHECK (transportation_fee_mmk <> 'NaN'::numeric AND loading_fee_mmk <> 'NaN'::numeric AND unloading_fee_mmk <> 'NaN'::numeric AND other_fee_mmk <> 'NaN'::numeric AND total_mmk <> 'NaN'::numeric);

ALTER TABLE app.shipment_expenses ADD CONSTRAINT shipment_expenses_finite_numbers CHECK (amount_original <> 'NaN'::numeric AND mmk_per_unit <> 'NaN'::numeric AND amount_mmk <> 'NaN'::numeric);

ALTER TABLE app.goods_receiving_items ADD CONSTRAINT goods_receiving_items_finite_numbers CHECK (expected_quantity <> 'NaN'::numeric AND received_quantity <> 'NaN'::numeric AND damaged_quantity <> 'NaN'::numeric AND missing_quantity <> 'NaN'::numeric AND excess_quantity <> 'NaN'::numeric);

ALTER TABLE app.batches ADD CONSTRAINT batches_finite_numbers CHECK (purchase_cost_mmk <> 'NaN'::numeric AND transport_cost_mmk <> 'NaN'::numeric AND other_cost_mmk <> 'NaN'::numeric AND sellable_quantity <> 'NaN'::numeric AND total_cost_mmk <> 'NaN'::numeric AND actual_unit_cost_mmk <> 'NaN'::numeric);
