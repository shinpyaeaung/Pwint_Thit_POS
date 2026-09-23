CREATE TABLE app.expense_categories (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.expenses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), category_id uuid NOT NULL REFERENCES app.expense_categories(id),
 description text NOT NULL, incurred_at timestamptz NOT NULL,
 currency_code text NOT NULL REFERENCES app.currencies(code), amount_original numeric(20,4) NOT NULL CHECK(amount_original>0),
 mmk_per_unit numeric(24,10) NOT NULL CHECK(mmk_per_unit>0),
 amount_mmk numeric(20,4) GENERATED ALWAYS AS (round(amount_original*mmk_per_unit,4)) STORED,
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')), posted_at timestamptz,
 recorded_by uuid NOT NULL REFERENCES app.users(id), notes text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(currency_code<>'MMK' OR mmk_per_unit=1), CHECK((status IN ('POSTED','REVERSED'))=(posted_at IS NOT NULL))
);
CREATE TABLE app.payments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), payment_number text NOT NULL UNIQUE,
 direction text NOT NULL CHECK(direction IN ('IN','OUT')),
 method text NOT NULL CHECK(method IN ('CASH','BANK_TRANSFER','MOBILE_PAYMENT','OTHER')),
 currency_code text NOT NULL REFERENCES app.currencies(code), amount_original numeric(20,4) NOT NULL CHECK(amount_original>0),
 mmk_per_unit numeric(24,10) NOT NULL CHECK(mmk_per_unit>0),
 amount_mmk numeric(20,4) GENERATED ALWAYS AS (round(amount_original*mmk_per_unit,4)) STORED,
 customer_id uuid REFERENCES app.customers(id), supplier_id uuid REFERENCES app.suppliers(id),
 paid_at timestamptz NOT NULL, reference_number text, notes text,
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN ('DRAFT','POSTED','CANCELLED','REVERSED')), posted_at timestamptz,
 reverses_payment_id uuid UNIQUE REFERENCES app.payments(id),
 recorded_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(currency_code<>'MMK' OR mmk_per_unit=1), CHECK(num_nonnulls(customer_id,supplier_id)<=1),
 CHECK((status IN ('POSTED','REVERSED'))=(posted_at IS NOT NULL)), CHECK(reverses_payment_id IS NULL OR reverses_payment_id<>id)
);
CREATE TABLE app.payment_allocations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), payment_id uuid NOT NULL REFERENCES app.payments(id),
 sale_id uuid REFERENCES app.sales(id), purchase_id uuid REFERENCES app.purchases(id),
 sales_return_id uuid REFERENCES app.sales_returns(id), purchase_return_id uuid REFERENCES app.purchase_returns(id),
 expense_id uuid REFERENCES app.expenses(id), transportation_stage_id uuid REFERENCES app.transportation_stages(id),
 shipment_expense_id uuid REFERENCES app.shipment_expenses(id),
 settlement_mmk numeric(20,4) NOT NULL CHECK(settlement_mmk>0),
 applied_mmk numeric(20,4) NOT NULL CHECK(applied_mmk>0),
 applied_original numeric(20,4) NOT NULL CHECK(applied_original>0),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(num_nonnulls(sale_id,purchase_id,sales_return_id,purchase_return_id,expense_id,transportation_stage_id,shipment_expense_id)=1)
);
CREATE TABLE app.approvals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), permission_code text NOT NULL REFERENCES app.permissions(code),
 sale_id uuid REFERENCES app.sales(id), purchase_id uuid REFERENCES app.purchases(id),
 sales_return_id uuid REFERENCES app.sales_returns(id), purchase_return_id uuid REFERENCES app.purchase_returns(id),
 stock_adjustment_id uuid REFERENCES app.stock_adjustments(id), shipment_id uuid REFERENCES app.shipments(id),
 payment_id uuid REFERENCES app.payments(id), stock_take_id uuid REFERENCES app.stock_takes(id),
 requested_by uuid NOT NULL REFERENCES app.users(id), requested_at timestamptz NOT NULL DEFAULT now(), reason text NOT NULL,
 -- Snapshot/hash binds an approval to the exact proposed action; later services must compare before consuming.
 request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
 request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','REJECTED','CANCELLED')),
 decided_by uuid REFERENCES app.users(id), decided_at timestamptz, decision_note text, consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(num_nonnulls(sale_id,purchase_id,sales_return_id,purchase_return_id,stock_adjustment_id,shipment_id,payment_id,stock_take_id)=1),
 CHECK((status IN ('APPROVED','REJECTED'))=(decided_by IS NOT NULL AND decided_at IS NOT NULL)),
 CHECK((decided_by IS NULL)=(decided_at IS NULL)),
 CHECK(consumed_at IS NULL OR (status='APPROVED' AND consumed_at>=decided_at))
);
CREATE INDEX approvals_pending ON app.approvals(requested_at) WHERE status='PENDING';
CREATE TABLE app.audit_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid REFERENCES app.users(id),
 action text NOT NULL, entity_type text NOT NULL, entity_id uuid,
 old_value jsonb, new_value jsonb, request_id text, reason text,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(old_value IS NOT NULL OR new_value IS NOT NULL OR reason IS NOT NULL)
);
CREATE INDEX audit_logs_entity_history ON app.audit_logs(entity_type,entity_id,created_at);
CREATE INDEX audit_logs_date ON app.audit_logs(created_at);
CREATE TABLE app.attachments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), storage_key text NOT NULL UNIQUE,
 original_filename text NOT NULL, media_type text NOT NULL, size_bytes bigint NOT NULL CHECK(size_bytes>0),
 sha256 bytea NOT NULL CHECK(octet_length(sha256)=32), uploaded_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(), archived_at timestamptz
);
CREATE TABLE app.attachment_links (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), attachment_id uuid NOT NULL REFERENCES app.attachments(id),
 product_id uuid REFERENCES app.products(id), purchase_id uuid REFERENCES app.purchases(id),
 shipment_id uuid REFERENCES app.shipments(id), transportation_stage_id uuid REFERENCES app.transportation_stages(id),
 payment_id uuid REFERENCES app.payments(id), expense_id uuid REFERENCES app.expenses(id),
 damaged_product_id uuid REFERENCES app.damaged_products(id), missing_product_id uuid REFERENCES app.missing_products(id),
 goods_receiving_id uuid REFERENCES app.goods_receiving(id), sale_id uuid REFERENCES app.sales(id),
 sales_return_id uuid REFERENCES app.sales_returns(id), purchase_return_id uuid REFERENCES app.purchase_returns(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(num_nonnulls(product_id,purchase_id,shipment_id,transportation_stage_id,payment_id,expense_id,damaged_product_id,missing_product_id,goods_receiving_id,sale_id,sales_return_id,purchase_return_id)=1)
);

ALTER TABLE app.expenses ADD CONSTRAINT expenses_finite_numbers CHECK (amount_original <> 'NaN'::numeric AND mmk_per_unit <> 'NaN'::numeric AND amount_mmk <> 'NaN'::numeric);

ALTER TABLE app.payments ADD CONSTRAINT payments_finite_numbers CHECK (amount_original <> 'NaN'::numeric AND mmk_per_unit <> 'NaN'::numeric AND amount_mmk <> 'NaN'::numeric);

ALTER TABLE app.payment_allocations ADD CONSTRAINT payment_allocations_finite_numbers CHECK (settlement_mmk <> 'NaN'::numeric AND applied_mmk <> 'NaN'::numeric AND applied_original <> 'NaN'::numeric);
