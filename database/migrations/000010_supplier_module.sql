ALTER TABLE app.suppliers ADD COLUMN archived_at timestamptz;
ALTER TABLE app.suppliers ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK(version>0);
ALTER TABLE app.suppliers ADD CONSTRAINT supplier_code_valid CHECK(btrim(code)<>'' AND length(code)<=100);
ALTER TABLE app.suppliers ADD CONSTRAINT archived_supplier_inactive CHECK(archived_at IS NULL OR NOT is_active);
CREATE UNIQUE INDEX suppliers_code_ci ON app.suppliers(lower(code));
CREATE INDEX suppliers_page ON app.suppliers(created_at DESC,id);
CREATE INDEX suppliers_country_status ON app.suppliers(country_code,is_active) WHERE archived_at IS NULL;
CREATE INDEX purchases_supplier_history ON app.purchases(supplier_id,purchased_at DESC,id);
CREATE FUNCTION app.bump_supplier_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.version=OLD.version+1; RETURN NEW; END $$;
CREATE TRIGGER supplier_version BEFORE UPDATE ON app.suppliers FOR EACH ROW EXECUTE FUNCTION app.bump_supplier_version();
INSERT INTO app.permissions(code,description,is_sensitive) VALUES
 ('suppliers.view','View suppliers and contact details',false),('suppliers.create','Create suppliers',false),('suppliers.update','Update suppliers',false),('suppliers.delete','Archive suppliers while preserving purchases',true);
INSERT INTO app.user_permissions(user_id,permission_code,granted_by)
SELECT u.user_id,p.code,u.granted_by FROM app.user_permissions u CROSS JOIN (VALUES('suppliers.view'),('suppliers.create'),('suppliers.update'),('suppliers.delete')) p(code) WHERE u.permission_code='suppliers.manage';
CREATE FUNCTION app.supplier_document(s app.suppliers) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',s.id, 'code',s.code, 'name',s.name, 'contact_person',s.contact_person, 'phone',s.phone, 'address',s.address, 'country_code',s.country_code, 'supplier_type',s.supplier_type, 'payment_terms',s.payment_terms, 'notes',s.notes, 'is_active',s.is_active, 'archived_at',s.archived_at, 'created_at',s.created_at, 'updated_at',s.updated_at, 'version',s.version::text)
$$;
