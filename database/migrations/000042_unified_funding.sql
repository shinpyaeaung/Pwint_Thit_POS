-- One immutable ledger for business accounts and third-party liabilities.
CREATE TABLE app.creditors (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE CHECK(length(btrim(name)) BETWEEN 1 AND 100),
 contact text NOT NULL DEFAULT '' CHECK(length(contact)<=200), request_id uuid NOT NULL UNIQUE,
 request_payload jsonb NOT NULL, created_by uuid NOT NULL REFERENCES app.users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.creditors FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
ALTER TABLE app.account_entries ALTER COLUMN account_id DROP NOT NULL,
 ADD COLUMN creditor_id uuid REFERENCES app.creditors(id),
 ADD COLUMN payer text NOT NULL DEFAULT '', ADD COLUMN payee text NOT NULL DEFAULT '',
 ADD COLUMN method text NOT NULL DEFAULT 'OTHER', ADD COLUMN reference text NOT NULL DEFAULT '';
ALTER TABLE app.account_entries ADD CONSTRAINT ledger_owner CHECK(num_nonnulls(account_id,creditor_id)=1);
ALTER TABLE app.account_entries DROP CONSTRAINT account_entries_payment_id_key;
CREATE UNIQUE INDEX account_payment_once ON app.account_entries(payment_id) WHERE account_id IS NOT NULL;
CREATE UNIQUE INDEX creditor_payment_once ON app.account_entries(payment_id) WHERE creditor_id IS NOT NULL;
CREATE INDEX creditor_history ON app.account_entries(creditor_id,occurred_at,sequence);
-- Both sides of a repayment use PAYMENT: the account decreases and the liability decreases.
CREATE TABLE app.creditor_repayments (
 request_id uuid PRIMARY KEY, creditor_id uuid NOT NULL REFERENCES app.creditors(id),
 payment_id uuid NOT NULL UNIQUE REFERENCES app.payments(id), actor_id uuid NOT NULL REFERENCES app.users(id), payload jsonb NOT NULL
);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.creditor_repayments FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();

CREATE FUNCTION app.creditor_create(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.creditors; result uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.creditors WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
  IF old.request_payload<>d OR old.created_by<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF;
  RETURN old.id;
 END IF;
 INSERT INTO app.creditors(name,contact,request_id,request_payload,created_by)
 VALUES(btrim(d->>'name'),coalesce(d->>'contact',''),(d->>'request_id')::uuid,d,actor) RETURNING id INTO result;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'creditors.create','creditors',result,d);
 RETURN result;
END $$;

-- Account row locks serialize every debit, including concurrent payments from different modules.
CREATE OR REPLACE FUNCTION app.guard_active_account_entry() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE active boolean; available numeric; lowest numeric; account_name text;
BEGIN
 IF NEW.creditor_id IS NOT NULL THEN
  PERFORM 1 FROM app.creditors WHERE id=NEW.creditor_id FOR UPDATE;
  IF NEW.amount_mmk<0 THEN
   SELECT coalesce(sum(amount_mmk),0) INTO available FROM app.account_entries WHERE creditor_id=NEW.creditor_id AND occurred_at<=NEW.occurred_at;
   SELECT min(balance) INTO lowest FROM (SELECT occurred_at,sum(amount_mmk) OVER(ORDER BY occurred_at,sequence ROWS UNBOUNDED PRECEDING) AS balance FROM app.account_entries WHERE creditor_id=NEW.creditor_id) b WHERE occurred_at>NEW.occurred_at;
   IF least(available,coalesce(lowest,available))+NEW.amount_mmk<0 THEN
    RAISE EXCEPTION 'finance: Amount exceeds the remaining creditor balance. Correct repayments before reversing the funded payment.' USING ERRCODE='23514';
   END IF;
  END IF;
  RETURN NEW;
 END IF;
 SELECT is_active,name INTO active,account_name FROM app.money_accounts WHERE id=NEW.account_id FOR UPDATE;
 IF NOT active AND NOT (NEW.kind='PAYMENT' AND nullif(current_setting('app.reversal_original_payment',true),'') IS NOT NULL) THEN
  RAISE EXCEPTION 'finance: This account is archived. Restore it before recording transactions.' USING ERRCODE='23514';
 END IF;
 IF NEW.amount_mmk<0 THEN
  SELECT coalesce(sum(amount_mmk),0) INTO available FROM app.account_entries WHERE account_id=NEW.account_id AND occurred_at<=NEW.occurred_at;
  SELECT min(balance) INTO lowest FROM (
   SELECT occurred_at,sum(amount_mmk) OVER(ORDER BY occurred_at,sequence ROWS UNBOUNDED PRECEDING) AS balance
   FROM app.account_entries WHERE account_id=NEW.account_id
  ) b WHERE occurred_at>NEW.occurred_at;
  IF least(available,coalesce(lowest,available))+NEW.amount_mmk<0 THEN
   RAISE EXCEPTION 'finance: Insufficient funds in %. Choose a funded account or third-party funding.',account_name USING ERRCODE='23514';
  END IF;
 END IF;
 IF NEW.payer='' THEN NEW.payer=CASE WHEN NEW.amount_mmk<0 THEN account_name ELSE coalesce(nullif(NEW.sender,''),'External party') END; END IF;
 IF NEW.payee='' THEN NEW.payee=CASE WHEN NEW.amount_mmk>0 THEN account_name ELSE 'Personal expense / balance correction' END; END IF;
 RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION app.capture_account_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE account uuid; creditor uuid; original uuid; liability_repayment uuid;
 payee_name text; account_name text; creditor_name text;
BEGIN
 IF NEW.status<>'POSTED' OR (TG_OP='UPDATE' AND OLD.status='POSTED') THEN RETURN NEW; END IF;
 account=nullif(current_setting('app.payment_account',true),'')::uuid;
 creditor=nullif(current_setting('app.payment_creditor',true),'')::uuid;
 liability_repayment=nullif(current_setting('app.repayment_creditor',true),'')::uuid;
 original=nullif(current_setting('app.reversal_original_payment',true),'')::uuid;
 IF original IS NOT NULL THEN
  SELECT e.account_id INTO account FROM app.account_entries e WHERE e.payment_id=original AND e.account_id IS NOT NULL;
  SELECT e.creditor_id INTO creditor FROM app.account_entries e WHERE e.payment_id=original AND e.creditor_id IS NOT NULL;
  IF account IS NULL AND creditor IS NULL THEN RETURN NEW; END IF; -- Legacy unassigned reversal lineage.
  IF account IS NOT NULL AND creditor IS NOT NULL THEN liability_repayment=creditor; creditor=NULL; END IF;
 END IF;
 IF num_nonnulls(account,creditor)<>1 THEN RAISE EXCEPTION 'finance: Select exactly one paying/receiving account or third-party creditor.' USING ERRCODE='23514'; END IF;
 IF NEW.paid_at>now() THEN RAISE EXCEPTION 'finance: Payment date cannot be in the future.' USING ERRCODE='23514'; END IF;
 payee_name=coalesce((SELECT name FROM app.suppliers WHERE id=NEW.supplier_id),(SELECT name FROM app.customers WHERE id=NEW.customer_id),
  (SELECT t.provider_name FROM app.payment_allocations a JOIN app.transportation_stages t ON t.id=a.transportation_stage_id WHERE a.payment_id=coalesce(original,NEW.id) LIMIT 1),
  (SELECT e.description FROM app.payment_allocations a JOIN app.expenses e ON e.id=a.expense_id WHERE a.payment_id=coalesce(original,NEW.id) LIMIT 1),
  (SELECT e.description FROM app.payment_allocations a JOIN app.shipment_expenses e ON e.id=a.shipment_expense_id WHERE a.payment_id=coalesce(original,NEW.id) LIMIT 1),
  CASE WHEN NEW.direction='IN' THEN 'Walk-in customer' ELSE 'Business payment' END);
 IF creditor IS NOT NULL THEN
  IF original IS NULL AND (NEW.direction<>'OUT' OR current_setting('app.allow_creditor',true) IS DISTINCT FROM '1') THEN RAISE EXCEPTION 'finance: Third-party funding is only available for suppliers, transportation and operating expenses.' USING ERRCODE='23514'; END IF;
  SELECT name INTO creditor_name FROM app.creditors WHERE id=creditor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'finance: Choose a creditor.' USING ERRCODE='23514'; END IF;
  INSERT INTO app.account_entries(creditor_id,kind,amount_mmk,description,occurred_at,recorded_by,payment_id,payer,payee,method,reference)
  VALUES(creditor,'PAYMENT',CASE WHEN NEW.direction='OUT' THEN NEW.amount_mmk ELSE -NEW.amount_mmk END,NEW.payment_number,NEW.paid_at,NEW.recorded_by,NEW.id,
   CASE WHEN NEW.direction='OUT' THEN creditor_name ELSE payee_name END,CASE WHEN NEW.direction='OUT' THEN payee_name ELSE creditor_name END,NEW.method,coalesce(NEW.reference_number,''));
  RETURN NEW;
 END IF;
 -- Lock creditor first for repayment, then account: consistent with repayments and source reversals.
 IF liability_repayment IS NOT NULL THEN SELECT name INTO creditor_name FROM app.creditors WHERE id=liability_repayment FOR UPDATE; END IF;
 SELECT name INTO account_name FROM app.money_accounts WHERE id=account FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Account not found.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM app.account_entries WHERE account_id=account AND kind='BALANCE_ADJUSTMENT' AND occurred_at>=NEW.paid_at) THEN RAISE EXCEPTION 'finance: Payment date is already reconciled. Choose a later date.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.account_entries(account_id,kind,amount_mmk,description,occurred_at,recorded_by,payment_id,payer,payee,method,reference)
 VALUES(account,'PAYMENT',CASE WHEN NEW.direction='IN' THEN NEW.amount_mmk ELSE -NEW.amount_mmk END,NEW.payment_number,NEW.paid_at,NEW.recorded_by,NEW.id,
  CASE WHEN NEW.direction='OUT' THEN account_name ELSE coalesce(creditor_name,payee_name) END,CASE WHEN NEW.direction='IN' THEN account_name ELSE coalesce(creditor_name,payee_name) END,NEW.method,coalesce(NEW.reference_number,''));
 IF liability_repayment IS NOT NULL THEN
  INSERT INTO app.account_entries(creditor_id,kind,amount_mmk,description,occurred_at,recorded_by,payment_id,payer,payee,method,reference)
  VALUES(liability_repayment,'PAYMENT',CASE WHEN NEW.direction='OUT' THEN -NEW.amount_mmk ELSE NEW.amount_mmk END,NEW.payment_number,NEW.paid_at,NEW.recorded_by,NEW.id,CASE WHEN NEW.direction='OUT' THEN account_name ELSE creditor_name END,CASE WHEN NEW.direction='OUT' THEN creditor_name ELSE account_name END,NEW.method,coalesce(NEW.reference_number,''));
 END IF;
 RETURN NEW;
END $$;

-- Extend only the authorized outgoing workflows; their original transactions and deduplication remain intact.
DO $$ DECLARE signature text; definition text; needle text;
BEGIN
 FOREACH signature IN ARRAY ARRAY['app.record_supplier_payment(uuid,uuid,jsonb)','app.transport_payment(jsonb,uuid)','app.expense_post(jsonb,uuid)'] LOOP
  definition=pg_get_functiondef(signature::regprocedure);
  needle=CASE WHEN signature LIKE '%record_supplier%' THEN 'result=app.record_supplier_payment_before_accounts(purchase,actor,data);' ELSE CASE WHEN signature LIKE '%transport%' THEN 'result=app.transport_payment_before_accounts(d,actor);' ELSE 'result=app.expense_post_before_accounts(d,actor);' END END;
  IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected funding wrapper: %',signature; END IF;
  definition=replace(definition,needle,
   'PERFORM set_config(''app.payment_creditor'',coalesce('||CASE WHEN signature LIKE '%record_supplier%' THEN 'data' ELSE 'd' END||'->>''creditor_id'',''''),true); PERFORM set_config(''app.allow_creditor'',''1'',true); '||needle||' PERFORM set_config(''app.payment_creditor'','''',true); PERFORM set_config(''app.allow_creditor'','''',true);');
  EXECUTE definition;
 END LOOP;
END $$;
CREATE FUNCTION app.creditor_repay(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE prior app.creditor_repayments; creditor uuid=(d->>'creditor_id')::uuid; value numeric=(d->>'amount_mmk')::numeric;
 payment uuid; available numeric; effective timestamptz=(d->>'paid_at')::timestamptz;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO prior FROM app.creditor_repayments WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF prior.payload<>d OR prior.actor_id<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF; RETURN prior.payment_id; END IF;
 PERFORM 1 FROM app.creditors WHERE id=creditor FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Choose a creditor.' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(amount_mmk),0) INTO available FROM app.account_entries WHERE creditor_id=creditor AND occurred_at<=effective;
 IF value IS NULL OR value='NaN' OR value<=0 OR scale(value)>4 OR value>available OR effective>now() THEN RAISE EXCEPTION 'finance: Enter a positive repayment within the balance at the selected date (% MMK) and no later than now.',available USING ERRCODE='23514'; END IF;
 PERFORM set_config('app.payment_account',coalesce(d->>'account_id',''),true);
 PERFORM set_config('app.payment_creditor','',true);
 PERFORM set_config('app.repayment_creditor',creditor::text,true);
 INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,paid_at,reference_number,notes,recorded_by)
 VALUES('','OUT',d->>'method','MMK',value,1,effective,d->>'reference',d->>'notes',actor) RETURNING id INTO payment;
 UPDATE app.payments SET status='POSTED',posted_at=clock_timestamp() WHERE id=payment;
 INSERT INTO app.creditor_repayments VALUES((d->>'request_id')::uuid,creditor,payment,actor,d);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'creditors.repay','payments',payment,d);
 PERFORM set_config('app.payment_account','',true); PERFORM set_config('app.repayment_creditor','',true);
 RETURN payment;
END $$;
CREATE TABLE app.creditor_repayment_reversals (
 request_id uuid PRIMARY KEY, original_payment_id uuid NOT NULL UNIQUE REFERENCES app.payments(id),
 payment_id uuid NOT NULL UNIQUE REFERENCES app.payments(id), actor_id uuid NOT NULL REFERENCES app.users(id), payload jsonb NOT NULL
);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.creditor_repayment_reversals FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE FUNCTION app.creditor_repayment_reverse(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE previous app.creditor_repayment_reversals; source app.payments; creditor uuid=(d->>'creditor_id')::uuid; result uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO previous FROM app.creditor_repayment_reversals WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF previous.payload<>d OR previous.actor_id<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF; RETURN previous.payment_id; END IF;
 PERFORM 1 FROM app.creditors WHERE id=creditor FOR UPDATE;
 SELECT p.* INTO source FROM app.payments p JOIN app.creditor_repayments r ON r.payment_id=p.id WHERE r.creditor_id=creditor AND p.id=(d->>'payment_id')::uuid FOR UPDATE OF p;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM app.creditor_repayment_reversals WHERE original_payment_id=source.id) OR nullif(btrim(d->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'finance: Choose an unreversed creditor repayment and enter a reason.' USING ERRCODE='23514'; END IF;
 PERFORM set_config('app.reversal_original_payment',source.id::text,true);
 INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,paid_at,reference_number,recorded_by)
 VALUES('','IN',source.method,'MMK',source.amount_mmk,1,now(),d->>'reason',actor) RETURNING id INTO result;
 UPDATE app.payments SET status='POSTED',posted_at=now() WHERE id=result;
 INSERT INTO app.creditor_repayment_reversals VALUES((d->>'request_id')::uuid,source.id,result,actor,d);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'creditors.repayment_reverse','payments',result,d);
 PERFORM set_config('app.reversal_original_payment','',true);
 RETURN result;
END $$;
