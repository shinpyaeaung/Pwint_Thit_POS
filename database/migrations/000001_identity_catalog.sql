CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE app.roles (
 code text PRIMARY KEY CHECK (code IN ('SUPER_ADMIN','STAFF_ADMIN')),
 name text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app.roles(code,name) VALUES ('SUPER_ADMIN','Super Admin'),('STAFF_ADMIN','Staff Admin');

CREATE TABLE app.users (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 username text NOT NULL CHECK (length(btrim(username)) BETWEEN 3 AND 100),
 display_name text NOT NULL CHECK (btrim(display_name) <> ''),
 password_hash text NOT NULL CHECK (length(password_hash) >= 20),
 role_code text NOT NULL REFERENCES app.roles(code),
 is_active boolean NOT NULL DEFAULT true,
 password_changed_at timestamptz NOT NULL DEFAULT now(),
 last_login_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_username_ci ON app.users(lower(username));

CREATE TABLE app.permissions (
 code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*[.][a-z][a-z0-9_]*$'),
 description text NOT NULL,
 is_sensitive boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.user_permissions (
 user_id uuid NOT NULL REFERENCES app.users(id),
 permission_code text NOT NULL REFERENCES app.permissions(code),
 granted_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,permission_code)
);
CREATE TABLE app.user_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES app.users(id),
 token_hash bytea NOT NULL UNIQUE CHECK (octet_length(token_hash)=32),
 created_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 revoked_at timestamptz,
 CHECK (expires_at > created_at),
 CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE INDEX user_sessions_expiry ON app.user_sessions(expires_at) WHERE revoked_at IS NULL;

CREATE TABLE app.currencies (
 code text PRIMARY KEY CHECK (code ~ '^[A-Z]{3}$'),
 name text NOT NULL,
 minor_units smallint NOT NULL DEFAULT 2 CHECK (minor_units BETWEEN 0 AND 6),
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app.currencies(code,name) VALUES ('MMK','Myanmar Kyat'),('INR','Indian Rupee'),('THB','Thai Baht'),('CNY','Chinese Yuan'),('USD','US Dollar');
CREATE TABLE app.exchange_rates (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 currency_code text NOT NULL REFERENCES app.currencies(code),
 mmk_per_unit numeric(24,10) NOT NULL CHECK (mmk_per_unit > 0),
 effective_at timestamptz NOT NULL,
 source text NOT NULL,
 recorded_by uuid NOT NULL REFERENCES app.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (currency_code <> 'MMK' OR mmk_per_unit=1),
 UNIQUE(currency_code,effective_at)
);

CREATE TABLE app.categories (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL CHECK (btrim(name)<>''),
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX categories_name_ci ON app.categories(lower(name));
CREATE TABLE app.brands (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL CHECK (btrim(name)<>''),
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX brands_name_ci ON app.brands(lower(name));
CREATE TABLE app.units (
 code text PRIMARY KEY, name text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app.units(code,name) VALUES ('PIECE','Piece'),('BOTTLE','Bottle'),('PACK','Pack'),('PACKET','Packet'),('BUNDLE','Bundle'),('BOX','Box'),('BAG','Bag'),('CARTON','Carton'),('CASE','Case'),('CARD','Card');
CREATE TABLE app.suppliers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code text NOT NULL UNIQUE, name text NOT NULL CHECK (btrim(name)<>''),
 contact_person text, phone text, address text, country_code text CHECK (country_code ~ '^[A-Z]{2}$'),
 supplier_type text, payment_terms text, notes text,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.customers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code text NOT NULL UNIQUE, name text NOT NULL CHECK (btrim(name)<>''),
 business_name text, phone text, address text,
 customer_type text NOT NULL DEFAULT 'RETAIL' CHECK (customer_type IN ('RETAIL','WHOLESALE')),
 credit_limit_mmk numeric(20,4) NOT NULL DEFAULT 0 CHECK (credit_limit_mmk>=0),
 notes text, is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.warehouses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code text NOT NULL UNIQUE, name text NOT NULL, address text,
 location_type text NOT NULL DEFAULT 'WAREHOUSE' CHECK(location_type IN ('WAREHOUSE','SHOP')),
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sku text NOT NULL UNIQUE, name text NOT NULL CHECK(btrim(name)<>''),
 barcode text UNIQUE CHECK (barcode IS NULL OR btrim(barcode)<>''),
 category_id uuid REFERENCES app.categories(id), brand_id uuid REFERENCES app.brands(id),
 country_code text CHECK(country_code ~ '^[A-Z]{2}$'), description text,
 base_unit_code text NOT NULL REFERENCES app.units(code),
 minimum_stock numeric(20,6) CHECK(minimum_stock>=0),
 tracks_expiry boolean NOT NULL DEFAULT false,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.product_units (
 product_id uuid NOT NULL REFERENCES app.products(id), unit_code text NOT NULL REFERENCES app.units(code),
 units_per_pack numeric(20,6) NOT NULL CHECK(units_per_pack>0), barcode text UNIQUE,
 retail_price_mmk numeric(20,4) CHECK(retail_price_mmk>=0),
 wholesale_price_mmk numeric(20,4) CHECK(wholesale_price_mmk>=0),
 is_default_purchase boolean NOT NULL DEFAULT false, is_default_sale boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(product_id,unit_code)
);
CREATE UNIQUE INDEX product_default_purchase_unit ON app.product_units(product_id) WHERE is_default_purchase;
CREATE UNIQUE INDEX product_default_sale_unit ON app.product_units(product_id) WHERE is_default_sale;
CREATE TABLE app.product_suppliers (
 product_id uuid NOT NULL REFERENCES app.products(id), supplier_id uuid NOT NULL REFERENCES app.suppliers(id),
 supplier_sku text, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(product_id,supplier_id)
);

ALTER TABLE app.exchange_rates ADD CONSTRAINT exchange_rates_finite_numbers CHECK (mmk_per_unit <> 'NaN'::numeric);

ALTER TABLE app.customers ADD CONSTRAINT customers_finite_numbers CHECK (credit_limit_mmk <> 'NaN'::numeric);

ALTER TABLE app.products ADD CONSTRAINT products_finite_numbers CHECK (minimum_stock <> 'NaN'::numeric);

ALTER TABLE app.product_units ADD CONSTRAINT product_units_finite_numbers CHECK (units_per_pack <> 'NaN'::numeric AND retail_price_mmk <> 'NaN'::numeric AND wholesale_price_mmk <> 'NaN'::numeric);
