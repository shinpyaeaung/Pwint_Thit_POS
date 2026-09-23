CREATE FUNCTION app.touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at=clock_timestamp(); RETURN NEW; END $$;
CREATE FUNCTION app.deny_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION '% is append-only; use a new record or reversal',TG_TABLE_NAME USING ERRCODE='23514'; END $$;
CREATE TRIGGER roles_fixed BEFORE UPDATE OR DELETE ON app.roles FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE TRIGGER exchange_rates_immutable BEFORE UPDATE OR DELETE ON app.exchange_rates FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE TRIGGER audit_logs_immutable BEFORE UPDATE OR DELETE ON app.audit_logs FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE TRIGGER inventory_movements_immutable BEFORE UPDATE OR DELETE ON app.inventory_movements FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();

-- Financial documents may be edited only before posting. Reversal preserves the original values.
CREATE FUNCTION app.protect_posted_document() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.posted_at IS NOT NULL THEN
  IF TG_OP='UPDATE' AND OLD.status='POSTED' AND NEW.status='REVERSED'
   AND (to_jsonb(NEW)-'status'-'updated_at')=(to_jsonb(OLD)-'status'-'updated_at') THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'posted % must be reversed, not edited or deleted',TG_TABLE_NAME USING ERRCODE='23514';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['purchases','sales','goods_receiving','sales_returns','purchase_returns','stock_adjustments','expenses','payments'] LOOP
  EXECUTE format('CREATE TRIGGER protect_posted BEFORE UPDATE OR DELETE ON app.%I FOR EACH ROW EXECUTE FUNCTION app.protect_posted_document()',t);
 END LOOP;
END $$;

-- Lock parent while editing children, so posting cannot race an item change.
CREATE FUNCTION app.protect_document_item() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_id uuid; locked_at timestamptz; row_data jsonb;
BEGIN
 FOR row_data IN SELECT value FROM jsonb_array_elements(
  CASE WHEN TG_OP='INSERT' THEN jsonb_build_array(to_jsonb(NEW))
       WHEN TG_OP='DELETE' THEN jsonb_build_array(to_jsonb(OLD))
       ELSE jsonb_build_array(to_jsonb(OLD),to_jsonb(NEW)) END) LOOP
  parent_id=(row_data->>TG_ARGV[1])::uuid;
  EXECUTE format('SELECT %I FROM app.%I WHERE id=$1 FOR UPDATE',TG_ARGV[2],TG_ARGV[0]) INTO locked_at USING parent_id;
  IF locked_at IS NOT NULL THEN RAISE EXCEPTION 'items of finalized % are immutable',TG_ARGV[0] USING ERRCODE='23514'; END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.purchase_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('purchases','purchase_id','posted_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.sale_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('sales','sale_id','posted_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.goods_receiving_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('goods_receiving','goods_receiving_id','posted_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.sales_return_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('sales_returns','sales_return_id','posted_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.purchase_return_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('purchase_returns','purchase_return_id','posted_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.stock_adjustment_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('stock_adjustments','stock_adjustment_id','posted_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.payment_allocations FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('payments','payment_id','posted_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.shipment_items FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('shipments','shipment_id','costs_finalized_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.transportation_stages FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('shipments','shipment_id','costs_finalized_at');
CREATE TRIGGER protect_parent BEFORE INSERT OR UPDATE OR DELETE ON app.shipment_expenses FOR EACH ROW EXECUTE FUNCTION app.protect_document_item('shipments','shipment_id','costs_finalized_at');

CREATE FUNCTION app.protect_finalized_batch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.finalized_at IS NOT NULL THEN RAISE EXCEPTION 'finalized batch costs are immutable' USING ERRCODE='23514'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER protect_batch BEFORE UPDATE OR DELETE ON app.batches FOR EACH ROW EXECUTE FUNCTION app.protect_finalized_batch();
CREATE FUNCTION app.protect_shipment_costs() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.costs_finalized_at IS NOT NULL AND (TG_OP='DELETE' OR NEW.costs_finalized_at IS DISTINCT FROM OLD.costs_finalized_at
  OR NEW.costs_finalized_by IS DISTINCT FROM OLD.costs_finalized_by OR NEW.allocation_method<>OLD.allocation_method) THEN
  RAISE EXCEPTION 'finalized shipment costing cannot be changed' USING ERRCODE='23514'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER protect_shipment BEFORE UPDATE OR DELETE ON app.shipments FOR EACH ROW EXECUTE FUNCTION app.protect_shipment_costs();

CREATE FUNCTION app.protect_sale_batch_cost() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE item uuid; posted timestamptz; row_data jsonb;
BEGIN
 FOR row_data IN SELECT value FROM jsonb_array_elements(CASE WHEN TG_OP='INSERT' THEN jsonb_build_array(to_jsonb(NEW)) WHEN TG_OP='DELETE' THEN jsonb_build_array(to_jsonb(OLD)) ELSE jsonb_build_array(to_jsonb(OLD),to_jsonb(NEW)) END) LOOP
  item=(row_data->>'sale_item_id')::uuid;
  SELECT s.posted_at INTO posted FROM app.sales s JOIN app.sale_items i ON i.sale_id=s.id WHERE i.id=item FOR UPDATE OF s;
  IF posted IS NOT NULL THEN RAISE EXCEPTION 'posted sale batch costs are immutable' USING ERRCODE='23514'; END IF;
 END LOOP;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER protect_sale_cost BEFORE INSERT OR UPDATE OR DELETE ON app.sale_item_batches FOR EACH ROW EXECUTE FUNCTION app.protect_sale_batch_cost();

-- Purchase snapshot must match a selected historical quote; manual quotes may omit exchange_rate_id.
CREATE FUNCTION app.validate_purchase_rate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.exchange_rate_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.exchange_rates r WHERE r.id=NEW.exchange_rate_id AND r.currency_code=NEW.currency_code AND r.mmk_per_unit=NEW.mmk_per_unit) THEN
 RAISE EXCEPTION 'purchase rate does not match selected historical quote' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER purchase_rate BEFORE INSERT OR UPDATE ON app.purchases FOR EACH ROW EXECUTE FUNCTION app.validate_purchase_rate();

-- Index every foreign-key tuple not already covered by a leading index prefix.
DO $$ DECLARE fk record; col_list text; BEGIN
 FOR fk IN SELECT c.oid,c.conrelid,c.conkey,cl.relname FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid JOIN pg_namespace n ON n.oid=cl.relnamespace WHERE n.nspname='app' AND c.contype='f' LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_index i WHERE i.indrelid=fk.conrelid AND i.indpred IS NULL AND i.indisvalid AND ARRAY(SELECT unnest(i.indkey) LIMIT cardinality(fk.conkey))=fk.conkey) THEN
   SELECT string_agg(quote_ident(a.attname),',' ORDER BY k.ord) INTO col_list FROM unnest(fk.conkey) WITH ORDINALITY k(attnum,ord) JOIN pg_attribute a ON a.attrelid=fk.conrelid AND a.attnum=k.attnum;
   EXECUTE format('CREATE INDEX %I ON app.%I (%s)','fk_'||fk.relname||'_'||substr(md5(col_list),1,8),fk.relname,col_list);
  END IF;
 END LOOP;
END $$;
DO $$ DECLARE t record; BEGIN
 FOR t IN SELECT table_name FROM information_schema.columns WHERE table_schema='app' AND column_name='updated_at' LOOP
  EXECUTE format('CREATE TRIGGER z_touch_updated_at BEFORE UPDATE ON app.%I FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at()',t.table_name);
 END LOOP;
END $$;
CREATE INDEX purchases_date ON app.purchases(purchased_at);
CREATE INDEX sales_date ON app.sales(sold_at);
CREATE INDEX purchases_due ON app.purchases(due_date) WHERE status='POSTED';
CREATE INDEX sales_due ON app.sales(due_date) WHERE status='POSTED';
CREATE INDEX payments_date ON app.payments(paid_at);
CREATE INDEX expenses_date ON app.expenses(incurred_at);
CREATE INDEX shipments_status_arrival ON app.shipments(status,expected_arrival_at);
CREATE INDEX products_name_search ON app.products(lower(name) text_pattern_ops);

CREATE VIEW app.purchase_totals AS
SELECT p.id AS purchase_id, p.supplier_id, p.currency_code, p.mmk_per_unit,
 COALESCE(sum(i.total_original),0)::numeric(20,4) AS total_original,
 round(COALESCE(sum(i.total_original),0)*p.mmk_per_unit,4)::numeric(20,4) AS total_mmk
FROM app.purchases p LEFT JOIN app.purchase_items i ON i.purchase_id=p.id GROUP BY p.id;
CREATE VIEW app.sale_totals AS
SELECT s.id AS sale_id, s.customer_id, COALESCE(sum(i.total_mmk),0)::numeric(20,4) AS total_mmk
FROM app.sales s LEFT JOIN app.sale_items i ON i.sale_id=s.id GROUP BY s.id;

CREATE VIEW app.customer_debts AS
WITH paid AS (
 SELECT a.sale_id,sum(a.applied_mmk) amount FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id
 WHERE p.status='POSTED' AND p.direction='IN' AND a.sale_id IS NOT NULL GROUP BY a.sale_id
), credits AS (
 SELECT r.sale_id,sum(i.refund_mmk) amount FROM app.sales_returns r JOIN app.sales_return_items i ON i.sales_return_id=r.id WHERE r.status='POSTED' GROUP BY r.sale_id
), refunds AS (
 SELECT r.sale_id,sum(a.applied_mmk) amount FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id JOIN app.sales_returns r ON r.id=a.sales_return_id
 WHERE p.status='POSTED' AND p.direction='OUT' AND r.status='POSTED' GROUP BY r.sale_id
), balances AS (
 SELECT s.id AS sale_id,s.customer_id,s.due_date,t.total_mmk,COALESCE(p.amount,0)::numeric(20,4) AS amount_paid_mmk,
 COALESCE(c.amount,0)::numeric(20,4) AS return_credit_mmk,COALESCE(r.amount,0)::numeric(20,4) AS refunded_mmk,
 (t.total_mmk-COALESCE(p.amount,0)-COALESCE(c.amount,0)+COALESCE(r.amount,0))::numeric(20,4) AS outstanding_mmk
 FROM app.sales s JOIN app.sale_totals t ON t.sale_id=s.id LEFT JOIN paid p ON p.sale_id=s.id LEFT JOIN credits c ON c.sale_id=s.id LEFT JOIN refunds r ON r.sale_id=s.id WHERE s.status='POSTED' AND s.customer_id IS NOT NULL
)
SELECT *, CASE WHEN outstanding_mmk<=0 THEN 'PAID' WHEN due_date<CURRENT_DATE THEN 'OVERDUE' WHEN amount_paid_mmk>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END AS payment_status FROM balances;

CREATE VIEW app.supplier_payables AS
WITH paid AS (
 SELECT a.purchase_id,sum(a.applied_mmk) amount,sum(a.applied_original) original FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id
 WHERE p.status='POSTED' AND p.direction='OUT' AND a.purchase_id IS NOT NULL GROUP BY a.purchase_id
), credits AS (
 SELECT r.purchase_id,sum(i.credit_mmk) amount,sum(i.credit_original) original FROM app.purchase_returns r JOIN app.purchase_return_items i ON i.purchase_return_id=r.id WHERE r.status='POSTED' GROUP BY r.purchase_id
), refunds AS (
 SELECT r.purchase_id,sum(a.applied_mmk) amount,sum(a.applied_original) original FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id JOIN app.purchase_returns r ON r.id=a.purchase_return_id
 WHERE p.status='POSTED' AND p.direction='IN' AND r.status='POSTED' GROUP BY r.purchase_id
), balances AS (
 SELECT p.id AS purchase_id,p.supplier_id,p.due_date,t.currency_code,t.total_original,t.total_mmk,
 COALESCE(x.amount,0)::numeric(20,4) AS amount_paid_mmk,
 (t.total_original-COALESCE(x.original,0)-COALESCE(c.original,0)+COALESCE(r.original,0))::numeric(20,4) AS outstanding_original,
 (t.total_mmk-COALESCE(x.amount,0)-COALESCE(c.amount,0)+COALESCE(r.amount,0))::numeric(20,4) AS outstanding_mmk
 FROM app.purchases p JOIN app.purchase_totals t ON t.purchase_id=p.id LEFT JOIN paid x ON x.purchase_id=p.id LEFT JOIN credits c ON c.purchase_id=p.id LEFT JOIN refunds r ON r.purchase_id=p.id WHERE p.status='POSTED'
)
SELECT *, CASE WHEN outstanding_original<=0 THEN 'PAID' WHEN due_date<CURRENT_DATE THEN 'OVERDUE' WHEN amount_paid_mmk>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END AS payment_status FROM balances;
