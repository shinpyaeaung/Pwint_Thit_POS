-- Readable identifiers are allocated under a transactional row lock per type/year.
-- UUID primary keys and all existing business identifiers remain unchanged.
CREATE TABLE app.business_number_counters (
 prefix text NOT NULL, year integer NOT NULL, last_value bigint NOT NULL CHECK(last_value>0),
 PRIMARY KEY(prefix,year)
);
CREATE FUNCTION app.next_business_number(kind text) RETURNS text LANGUAGE plpgsql VOLATILE AS $$
DECLARE y integer=extract(year FROM app.business_date()); n bigint;
BEGIN
 INSERT INTO app.business_number_counters(prefix,year,last_value) VALUES(kind,y,1)
 ON CONFLICT(prefix,year) DO UPDATE SET last_value=app.business_number_counters.last_value+1
 RETURNING last_value INTO n;
 RETURN kind||'-'||y||'-'||lpad(n::text,greatest(4,length(n::text)),'0');
END $$;
CREATE FUNCTION app.assign_business_number() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE value text; parts text[];
BEGIN
 value=to_jsonb(NEW)->>TG_ARGV[0];
 IF value IS NULL OR btrim(value)='' THEN
  NEW=jsonb_populate_record(NEW,jsonb_build_object(TG_ARGV[0],app.next_business_number(TG_ARGV[1])));
 ELSE
  parts=regexp_match(value,'^'||TG_ARGV[1]||'-([0-9]{4})-([0-9]{4,})$');
  IF parts IS NOT NULL AND parts[2]::bigint>0 THEN
   INSERT INTO app.business_number_counters(prefix,year,last_value) VALUES(TG_ARGV[1],parts[1]::integer,parts[2]::bigint)
   ON CONFLICT(prefix,year) DO UPDATE SET last_value=greatest(app.business_number_counters.last_value,excluded.last_value);
  END IF;
 END IF;
 RETURN NEW;
END $$;
INSERT INTO app.business_number_counters(prefix,year,last_value)
 SELECT 'PUR',split_part(purchase_number,'-',2)::integer,max(split_part(purchase_number,'-',3)::bigint)
 FROM app.purchases WHERE purchase_number ~ '^PUR-[0-9]{4}-[0-9]{4,}$'
 GROUP BY split_part(purchase_number,'-',2) ON CONFLICT(prefix,year) DO UPDATE SET last_value=greatest(app.business_number_counters.last_value,excluded.last_value);
CREATE TRIGGER business_number BEFORE INSERT ON app.purchases FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('purchase_number','PUR');
INSERT INTO app.business_number_counters(prefix,year,last_value)
 SELECT 'SHP',split_part(shipment_number,'-',2)::integer,max(split_part(shipment_number,'-',3)::bigint)
 FROM app.shipments WHERE shipment_number ~ '^SHP-[0-9]{4}-[0-9]{4,}$'
 GROUP BY split_part(shipment_number,'-',2) ON CONFLICT(prefix,year) DO UPDATE SET last_value=greatest(app.business_number_counters.last_value,excluded.last_value);
CREATE TRIGGER business_number BEFORE INSERT ON app.shipments FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('shipment_number','SHP');
INSERT INTO app.business_number_counters(prefix,year,last_value)
 SELECT 'GRN',split_part(receipt_number,'-',2)::integer,max(split_part(receipt_number,'-',3)::bigint)
 FROM app.goods_receiving WHERE receipt_number ~ '^GRN-[0-9]{4}-[0-9]{4,}$'
 GROUP BY split_part(receipt_number,'-',2) ON CONFLICT(prefix,year) DO UPDATE SET last_value=greatest(app.business_number_counters.last_value,excluded.last_value);
CREATE TRIGGER business_number BEFORE INSERT ON app.goods_receiving FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('receipt_number','GRN');
INSERT INTO app.business_number_counters(prefix,year,last_value)
 SELECT 'SUP',split_part(code,'-',2)::integer,max(split_part(code,'-',3)::bigint)
 FROM app.suppliers WHERE code ~ '^SUP-[0-9]{4}-[0-9]{4,}$'
 GROUP BY split_part(code,'-',2) ON CONFLICT(prefix,year) DO UPDATE SET last_value=greatest(app.business_number_counters.last_value,excluded.last_value);
CREATE TRIGGER business_number BEFORE INSERT ON app.suppliers FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('code','SUP');
INSERT INTO app.business_number_counters(prefix,year,last_value)
 SELECT 'PRD',split_part(sku,'-',2)::integer,max(split_part(sku,'-',3)::bigint)
 FROM app.products WHERE sku ~ '^PRD-[0-9]{4}-[0-9]{4,}$'
 GROUP BY split_part(sku,'-',2) ON CONFLICT(prefix,year) DO UPDATE SET last_value=greatest(app.business_number_counters.last_value,excluded.last_value);
CREATE TRIGGER business_number BEFORE INSERT ON app.products FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('sku','PRD');
INSERT INTO app.business_number_counters(prefix,year,last_value)
 SELECT 'PAY',split_part(payment_number,'-',2)::integer,max(split_part(payment_number,'-',3)::bigint)
 FROM app.payments WHERE payment_number ~ '^PAY-[0-9]{4}-[0-9]{4,}$'
 GROUP BY split_part(payment_number,'-',2) ON CONFLICT(prefix,year) DO UPDATE SET last_value=greatest(app.business_number_counters.last_value,excluded.last_value);
CREATE TRIGGER business_number BEFORE INSERT ON app.payments FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('payment_number','PAY');
INSERT INTO app.business_number_counters(prefix,year,last_value) SELECT 'INV',split_part(invoice_number,'-',2)::integer,max(split_part(invoice_number,'-',3)::bigint) FROM app.sales WHERE invoice_number ~ '^INV-[0-9]{4}-[0-9]{4,}$' GROUP BY split_part(invoice_number,'-',2);
CREATE TRIGGER business_number BEFORE INSERT ON app.sales FOR EACH ROW EXECUTE FUNCTION app.assign_business_number('invoice_number','INV');
ALTER TABLE app.sales ADD COLUMN order_number text NOT NULL DEFAULT app.next_business_number('SO') UNIQUE;
ALTER TABLE app.transportation_stages ADD COLUMN transportation_number text NOT NULL DEFAULT app.next_business_number('TRN') UNIQUE;
ALTER TABLE app.stock_adjustments ADD COLUMN adjustment_number text NOT NULL DEFAULT app.next_business_number('ADJ') UNIQUE;
ALTER TABLE app.damaged_products ADD COLUMN record_number text NOT NULL DEFAULT app.next_business_number('DMG') UNIQUE;
ALTER TABLE app.missing_products ADD COLUMN record_number text NOT NULL DEFAULT app.next_business_number('LOSS') UNIQUE;
DO $$ DECLARE f record; definition text;
BEGIN
 FOR f IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='app' AND p.prokind='f' AND p.proname IN ('pos_sale','customer_payment','sales_return_post','purchase_return_post','expense_post','expense_reverse') LOOP
  definition=pg_get_functiondef(f.oid);
  definition=replace(definition,'''PT-''||to_char(app.business_date(),''YYYYMMDD'')||''-''||lpad(nextval(''app.invoice_sequence'')::text,8,''0'')', 'app.next_business_number(''INV'')');
  definition=replace(definition,'''PAY-''||invoice', 'app.next_business_number(''PAY'')');
  definition=replace(definition,'''REF-''||result', 'app.next_business_number(''PAY'')');
  definition=replace(definition,'''SREF-''||result', 'app.next_business_number(''PAY'')');
  definition=replace(definition,'''EXP-''||expense', 'app.next_business_number(''PAY'')');
  definition=replace(definition, '''COL-''||(d->>''request_id'')', 'app.next_business_number(''PAY'')');
  definition=replace(definition, '''REV-''||p.id', 'app.next_business_number(''PAY'')');
  EXECUTE definition;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION app.stage_document(t app.transportation_stages, costs boolean) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',t.id,'transportation_number',t.transportation_number,'stage_number',t.stage_number,'start_location',t.start_location,'destination',t.destination,'provider_name',t.provider_name,'transportation_type',t.transportation_type,'vehicle_information',t.vehicle_information,'departed_at',t.departed_at,'arrived_at',t.arrived_at,'notes',t.notes,
 'payment_status',CASE WHEN paid.amount>=t.total_mmk THEN 'PAID' WHEN paid.amount>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END)
 || CASE WHEN costs THEN jsonb_build_object('transportation_fee_mmk',t.transportation_fee_mmk::text,'loading_fee_mmk',t.loading_fee_mmk::text,'unloading_fee_mmk',t.unloading_fee_mmk::text,'other_fee_mmk',t.other_fee_mmk::text,'total_mmk',t.total_mmk::text,'paid_mmk',paid.amount::text) ELSE '{}'::jsonb END
 FROM (SELECT COALESCE(sum(a.applied_mmk),0) amount FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.transportation_stage_id=t.id AND p.status='POSTED' AND p.direction='OUT') paid
$$;
