-- Corrections amend the purchase document, never rewrite posted stock/cost/payment facts.
CREATE TABLE app.purchase_corrections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), purchase_id uuid NOT NULL REFERENCES app.purchases(id),
 revision bigint NOT NULL CHECK(revision>0), request_id uuid NOT NULL UNIQUE, request_payload jsonb NOT NULL,
 before_document jsonb NOT NULL, after_document jsonb NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 2000),
 recorded_by uuid NOT NULL REFERENCES app.users(id), recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(purchase_id,revision)
);
CREATE TRIGGER purchase_corrections_immutable BEFORE UPDATE OR DELETE ON app.purchase_corrections FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE INDEX purchase_corrections_history ON app.purchase_corrections(purchase_id,recorded_at DESC,revision DESC);

CREATE FUNCTION app.purchase_record(purchase uuid, cutoff timestamptz DEFAULT 'infinity') RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT coalesce((SELECT after_document||jsonb_build_object('correction_version',revision::text,'corrected_at',recorded_at)
 FROM app.purchase_corrections WHERE purchase_id=p.id AND recorded_at<cutoff ORDER BY revision DESC LIMIT 1),
 jsonb_build_object('id',p.id,'purchase_number',p.purchase_number,'supplier_id',p.supplier_id,'supplier_name',s.name,
 'supplier_invoice_number',p.supplier_invoice_number,'purchased_at',p.purchased_at,'due_date',p.due_date,'currency_code',p.currency_code,
 'exchange_rate_id',p.exchange_rate_id,'mmk_per_unit',p.mmk_per_unit::text,'notes',p.notes,'created_at',p.created_at,
 'total_original',coalesce(a.amount_original,t.total_original)::text,'total_mmk',coalesce(a.amount_mmk,t.total_mmk)::text,'correction_version','0',
 'items',coalesce((SELECT jsonb_agg(jsonb_build_object('id',i.id,'product_id',i.product_id,'product_name',coalesce(i.product_name_snapshot,pr.name),'sku',coalesce(i.sku_snapshot,pr.sku),'unit_code',i.unit_code,'unit_name',coalesce(i.unit_name_snapshot,u.name),'quantity',i.quantity::text,'units_per_pack',i.units_per_pack::text,'base_quantity',i.base_quantity::text,'unit_price_original',i.unit_price_original::text,'discount_original',i.discount_original::text,'tax_original',i.tax_original::text,'total_original',i.total_original::text) ORDER BY i.line_number) FROM app.purchase_items i JOIN app.products pr ON pr.id=i.product_id JOIN app.units u ON u.code=i.unit_code WHERE i.purchase_id=p.id),'[]'::jsonb)))||jsonb_build_object('status',p.status)
 FROM app.purchases p JOIN app.suppliers s ON s.id=p.supplier_id JOIN app.purchase_totals t ON t.purchase_id=p.id LEFT JOIN app.purchase_amounts a ON a.purchase_id=p.id WHERE p.id=purchase
$$;

CREATE FUNCTION app.purchase_completed(purchase uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM app.purchase_items WHERE purchase_id=purchase)
 AND NOT EXISTS(SELECT 1 FROM app.purchase_items i WHERE i.purchase_id=purchase AND i.base_quantity<>(SELECT coalesce(sum(si.expected_quantity),0) FROM app.shipment_items si JOIN app.shipments sh ON sh.id=si.shipment_id WHERE si.purchase_item_id=i.id AND sh.status='RECEIVED'))
 AND NOT EXISTS(SELECT 1 FROM app.purchase_items i JOIN app.shipment_items si ON si.purchase_item_id=i.id JOIN app.shipments sh ON sh.id=si.shipment_id WHERE i.purchase_id=purchase AND sh.status NOT IN ('RECEIVED','CANCELLED'))
$$;

CREATE FUNCTION app.purchase_balance(purchase uuid, cutoff timestamptz DEFAULT 'infinity') RETURNS jsonb LANGUAGE sql STABLE AS $$
 WITH doc AS (SELECT app.purchase_record(purchase,cutoff) d), paid AS (
 SELECT coalesce(sum(a.applied_mmk),0) mmk,coalesce(sum(CASE WHEN p.currency_code=d->>'currency_code' THEN a.applied_original ELSE round(a.applied_mmk/(d->>'mmk_per_unit')::numeric,4) END),0) original
 FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id CROSS JOIN doc WHERE a.purchase_id=purchase AND p.status='POSTED' AND p.direction='OUT' AND p.paid_at<cutoff
 ), credits AS (
 SELECT coalesce(sum(i.credit_mmk),0) mmk,coalesce(sum(CASE WHEN p.currency_code=d->>'currency_code' THEN i.credit_original ELSE round(i.credit_mmk/(d->>'mmk_per_unit')::numeric,4) END),0) original
 FROM app.purchase_returns r JOIN app.purchase_return_items i ON i.purchase_return_id=r.id JOIN app.purchases p ON p.id=r.purchase_id CROSS JOIN doc WHERE r.purchase_id=purchase AND r.status='POSTED' AND r.returned_at<cutoff
 ), refunds AS (
 SELECT coalesce(sum(a.applied_mmk),0) mmk,coalesce(sum(CASE WHEN p.currency_code=d->>'currency_code' THEN a.applied_original ELSE round(a.applied_mmk/(d->>'mmk_per_unit')::numeric,4) END),0) original
 FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id JOIN app.purchase_returns r ON r.id=a.purchase_return_id CROSS JOIN doc WHERE r.purchase_id=purchase AND r.status='POSTED' AND p.status='POSTED' AND p.direction='IN' AND p.paid_at<cutoff
 ), amounts AS (SELECT d,paid.mmk paid,credits.mmk credits,refunds.mmk refunds,
 (d->>'total_original')::numeric-paid.original-credits.original+refunds.original AS outstanding_original,
 (d->>'total_mmk')::numeric-paid.mmk-credits.mmk+refunds.mmk AS original_outstanding_mmk FROM doc CROSS JOIN paid CROSS JOIN credits CROSS JOIN refunds)
 SELECT jsonb_build_object('amount_paid_mmk',paid::numeric(20,4)::text,'credits_mmk',credits::numeric(20,4)::text,'refunds_mmk',refunds::numeric(20,4)::text,
 'outstanding_original',outstanding_original::numeric(20,4)::text,
 'outstanding_mmk',(CASE WHEN d->>'correction_version'='0' THEN original_outstanding_mmk ELSE round(outstanding_original*(d->>'mmk_per_unit')::numeric,4) END)::numeric(20,4)::text) FROM amounts
$$;

CREATE OR REPLACE VIEW app.supplier_payables AS
WITH current AS (SELECT p.id,app.purchase_record(p.id) d,app.purchase_balance(p.id) b FROM app.purchases p WHERE p.status='POSTED'), balances AS (
 SELECT id AS purchase_id,(d->>'supplier_id')::uuid AS supplier_id,(d->>'due_date')::date AS due_date,d->>'currency_code' AS currency_code,
 (d->>'total_original')::numeric(20,4) AS total_original,(d->>'total_mmk')::numeric(20,4) AS total_mmk,
 (b->>'amount_paid_mmk')::numeric(20,4) AS amount_paid_mmk,(b->>'outstanding_original')::numeric(20,4) AS outstanding_original,(b->>'outstanding_mmk')::numeric(20,4) AS outstanding_mmk FROM current
) SELECT *,CASE WHEN outstanding_original<=0 THEN 'PAID' WHEN due_date<CURRENT_DATE THEN 'OVERDUE' WHEN amount_paid_mmk>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END AS payment_status FROM balances;

CREATE OR REPLACE FUNCTION app.purchase_document(p app.purchases, costs boolean, details boolean) RETURNS jsonb LANGUAGE sql STABLE AS $$
 WITH doc AS (SELECT app.purchase_record(p.id) d), filtered AS (
 SELECT CASE WHEN costs THEN d ELSE d-ARRAY['mmk_per_unit','exchange_rate_id','total_original','total_mmk'] END AS d FROM doc)
 SELECT (d-'items')||jsonb_build_object('can_view_cost',costs,'can_correct',p.status='POSTED' AND app.purchase_completed(p.id))
 ||CASE WHEN costs THEN app.purchase_balance(p.id)||jsonb_build_object('payment_status',(SELECT payment_status FROM app.supplier_payables WHERE purchase_id=p.id)) ELSE '{}'::jsonb END
 ||CASE WHEN details THEN jsonb_build_object('items',coalesce((SELECT jsonb_agg(CASE WHEN costs THEN item ELSE item-ARRAY['unit_price_original','discount_original','tax_original','total_original'] END) FROM jsonb_array_elements(d->'items') item),'[]'::jsonb)) ELSE '{}'::jsonb END FROM filtered
$$;

CREATE FUNCTION app.correct_purchase(purchase uuid, actor uuid, data jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p app.purchases; prior app.purchase_corrections; before_doc jsonb; after_doc jsonb; input jsonb:=data->'purchase';
 items jsonb:='[]'; x jsonb; prod app.products; unit_name text; line_total numeric(20,4); total numeric(20,4):=0; base numeric;
 revision bigint; result uuid; reason text:=btrim(data->>'reason');
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.users WHERE id=actor AND role_code='SUPER_ADMIN' AND is_active) THEN RAISE EXCEPTION 'correction: Only Super Admin can correct purchases.' USING ERRCODE='42501'; END IF;
 IF reason IS NULL OR length(reason)<1 OR length(reason)>2000 THEN RAISE EXCEPTION 'correction: Enter a correction reason (up to 2000 characters).' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(input->>'request_id',0));
 SELECT * INTO prior FROM app.purchase_corrections WHERE request_id=(input->>'request_id')::uuid;
 IF FOUND THEN IF prior.purchase_id<>purchase OR prior.request_payload<>data THEN RAISE EXCEPTION 'correction: Request already used with different changes.' USING ERRCODE='23514'; END IF; RETURN prior.id; END IF;
 SELECT * INTO p FROM app.purchases WHERE id=purchase FOR UPDATE;
 IF NOT FOUND OR p.status<>'POSTED' OR NOT app.purchase_completed(purchase) THEN RAISE EXCEPTION 'correction: Corrections require a completed purchase with all shipments received.' USING ERRCODE='23514'; END IF;
 before_doc:=app.purchase_record(purchase);revision:=(before_doc->>'correction_version')::bigint+1;
 IF (data->>'version') IS DISTINCT FROM (before_doc->>'correction_version') THEN RAISE EXCEPTION 'correction: Purchase changed. Reload before correcting.' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM app.suppliers WHERE id=(input->>'supplier_id')::uuid AND is_active AND archived_at IS NULL) OR NOT EXISTS(SELECT 1 FROM app.currencies WHERE code=input->>'currency_code' AND is_active) THEN RAISE EXCEPTION 'correction: Choose an active supplier and currency.' USING ERRCODE='23514'; END IF;
 IF (input->>'mmk_per_unit')::numeric<=0 OR (input->>'mmk_per_unit')::numeric='NaN'::numeric OR (input->>'currency_code'='MMK' AND (input->>'mmk_per_unit')::numeric<>1) THEN RAISE EXCEPTION 'correction: Invalid exchange rate.' USING ERRCODE='23514'; END IF;
 IF nullif(input->>'exchange_rate_id','') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.exchange_rates WHERE id=(input->>'exchange_rate_id')::uuid AND currency_code=input->>'currency_code' AND mmk_per_unit=(input->>'mmk_per_unit')::numeric AND effective_at<=(input->>'purchased_at')::timestamptz) THEN RAISE EXCEPTION 'correction: Historical quote does not match the corrected purchase.' USING ERRCODE='23514'; END IF;
 IF jsonb_array_length(input->'items') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'correction: Include 1–100 purchase items.' USING ERRCODE='23514'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(input->'items') LOOP
  SELECT * INTO prod FROM app.products WHERE id=(x->>'product_id')::uuid AND is_active AND archived_at IS NULL;
  SELECT name INTO unit_name FROM app.units WHERE code=x->>'unit_code';
  IF prod.id IS NULL OR unit_name IS NULL OR NOT EXISTS(SELECT 1 FROM app.product_units WHERE product_id=prod.id AND unit_code=x->>'unit_code') THEN RAISE EXCEPTION 'correction: Choose active products and configured units.' USING ERRCODE='23514'; END IF;
  IF (x->>'quantity')::numeric<=0 OR (x->>'units_per_pack')::numeric<=0 OR (x->>'unit_price_original')::numeric<0 OR (x->>'discount_original')::numeric<0 OR (x->>'tax_original')::numeric<0 OR (x->>'discount_original')::numeric>(x->>'quantity')::numeric*(x->>'unit_price_original')::numeric THEN RAISE EXCEPTION 'correction: Invalid item quantities or amounts.' USING ERRCODE='23514'; END IF;
  base:=(x->>'quantity')::numeric*(x->>'units_per_pack')::numeric;
  IF base<>round(base,6) THEN RAISE EXCEPTION 'correction: Base quantity exceeds six decimal places.' USING ERRCODE='23514'; END IF;
  line_total:=round((x->>'quantity')::numeric*(x->>'unit_price_original')::numeric-(x->>'discount_original')::numeric+(x->>'tax_original')::numeric,4);total:=total+line_total;
  items:=items||jsonb_build_array(x||jsonb_build_object('id',gen_random_uuid(),'product_name',prod.name,'sku',prod.sku,'unit_name',unit_name,'base_quantity',base::numeric(20,6)::text,'total_original',line_total::text));
 END LOOP;
 after_doc:=input-ARRAY['request_id','purchase_number']||jsonb_build_object('id',p.id,'purchase_number',p.purchase_number,'status',p.status,'created_at',p.created_at,'supplier_name',(SELECT name FROM app.suppliers WHERE id=(input->>'supplier_id')::uuid),'items',items,'total_original',total::text,'total_mmk',round(total*(input->>'mmk_per_unit')::numeric,4)::numeric(20,4)::text,'correction_version',revision::text,'due_date',nullif(input->>'due_date',''),'supplier_invoice_number',nullif(input->>'supplier_invoice_number',''),'exchange_rate_id',nullif(input->>'exchange_rate_id',''));
 INSERT INTO app.purchase_corrections(purchase_id,revision,request_id,request_payload,before_document,after_document,reason,recorded_by)
 VALUES(purchase,revision,(input->>'request_id')::uuid,data,before_doc,after_doc,reason,actor) RETURNING id INTO result;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value,reason) VALUES(actor,'purchases.correct','purchases',purchase,before_doc,after_doc,reason);
 RETURN result;
END $$;

-- Preserve invoice uniqueness for both new purchases and corrected references.
CREATE FUNCTION app.check_current_purchase_invoice(supplier uuid, invoice text, purchase uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF nullif(btrim(invoice),'') IS NULL THEN RETURN; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(supplier::text||':'||invoice,1));
 IF EXISTS(SELECT 1 FROM app.purchases p WHERE p.id IS DISTINCT FROM purchase AND (app.purchase_record(p.id)->>'supplier_id')::uuid=supplier AND app.purchase_record(p.id)->>'supplier_invoice_number'=invoice) THEN
 RAISE EXCEPTION 'correction: That supplier invoice already belongs to another purchase.' USING ERRCODE='23505'; END IF;
END $$;
CREATE FUNCTION app.check_new_purchase_invoice() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM app.check_current_purchase_invoice(NEW.supplier_id,NEW.supplier_invoice_number,NEW.id);RETURN NEW;END $$;
CREATE TRIGGER current_purchase_invoice BEFORE INSERT ON app.purchases FOR EACH ROW EXECUTE FUNCTION app.check_new_purchase_invoice();
CREATE FUNCTION app.check_corrected_purchase_invoice() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM app.check_current_purchase_invoice((NEW.after_document->>'supplier_id')::uuid,NEW.after_document->>'supplier_invoice_number',NEW.purchase_id);RETURN NEW;END $$;
CREATE TRIGGER current_purchase_invoice BEFORE INSERT ON app.purchase_corrections FOR EACH ROW EXECUTE FUNCTION app.check_corrected_purchase_invoice();

-- New settlements use the current revision; existing payment records retain their rates.
DO $$ DECLARE definition text; BEGIN
 definition:=pg_get_functiondef('app.record_supplier_payment(uuid,uuid,jsonb)'::regprocedure);
 definition:=replace(definition,'IF (data->>''paid_at'')::timestamptz<doc.purchased_at THEN', $patch$
 IF coalesce(data->>'correction_version','0')<>app.purchase_record(purchase)->>'correction_version' THEN RAISE EXCEPTION 'Purchase was corrected. Reload payment details.' USING ERRCODE='23514'; END IF;
 doc:=jsonb_populate_record(doc,app.purchase_record(purchase));
 IF (data->>'paid_at')::timestamptz<doc.purchased_at THEN$patch$);
 EXECUTE definition;
END $$;

DO $$ DECLARE definition text; BEGIN
 definition:=pg_get_functiondef('app.validate_payment_allocation()'::regprocedure);
 definition:=replace(definition,'SELECT supplier_id,mmk_per_unit INTO party,rate FROM app.purchases WHERE id=NEW.purchase_id;', $patch$
 SELECT (d->>'supplier_id')::uuid,(d->>'mmk_per_unit')::numeric INTO party,rate FROM (SELECT app.purchase_record(NEW.purchase_id) d) current;
$patch$);
 EXECUTE definition;
 definition:=pg_get_functiondef('app.record_supplier_payment(uuid,uuid,jsonb)'::regprocedure);
 definition:=replace(definition,'doc:=jsonb_populate_record(doc,app.purchase_record(purchase));', $patch$
 IF (app.purchase_record(purchase)->>'correction_version')<>'0' AND (data->>'paid_at')::timestamptz<(app.purchase_record(purchase)->>'corrected_at')::timestamptz THEN RAISE EXCEPTION 'A payment against corrected values cannot predate the correction.' USING ERRCODE='23514'; END IF;
 doc:=jsonb_populate_record(doc,app.purchase_record(purchase));
$patch$);
 EXECUTE definition;
END $$;
