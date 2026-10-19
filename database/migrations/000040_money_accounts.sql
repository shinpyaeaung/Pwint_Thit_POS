-- MMK account ledger: payments retain their original currency and historical conversion.
INSERT INTO app.permissions(code,description,is_sensitive) VALUES('accounts.view','View bank/cash balances and personal/external transactions',true),('accounts.manage','Manage accounts, deposits, personal spending and balance reconciliation',true);
CREATE TABLE app.money_accounts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 100),
 bank text NOT NULL CHECK(length(bank)<=100), reference text NOT NULL DEFAULT '' CHECK(length(reference)<=200),
 created_by uuid NOT NULL REFERENCES app.users(id), request_id uuid NOT NULL UNIQUE, request_payload jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(name)
);
CREATE TABLE app.account_entries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
 account_id uuid NOT NULL REFERENCES app.money_accounts(id),
 kind text NOT NULL CHECK(kind IN ('PAYMENT','EXTERNAL_DEPOSIT','PERSONAL_EXPENSE','BALANCE_ADJUSTMENT','REVERSAL')),
 amount_mmk numeric(20,4) NOT NULL CHECK(amount_mmk<>'NaN'),
 sender text NOT NULL DEFAULT '' CHECK(length(sender)<=200), description text NOT NULL CHECK(length(btrim(description)) BETWEEN 1 AND 1000),
 occurred_at timestamptz NOT NULL, recorded_by uuid NOT NULL REFERENCES app.users(id),
 payment_id uuid UNIQUE REFERENCES app.payments(id), reverses_id uuid UNIQUE REFERENCES app.account_entries(id),
 request_id uuid UNIQUE, request_payload jsonb, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK((kind='PAYMENT')=(payment_id IS NOT NULL)), CHECK((kind='REVERSAL')=(reverses_id IS NOT NULL)),
 CHECK(kind<>'EXTERNAL_DEPOSIT' OR (amount_mmk>0 AND btrim(sender)<>'')), CHECK(kind<>'PERSONAL_EXPENSE' OR amount_mmk<0)
);
CREATE INDEX account_history ON app.account_entries(account_id,occurred_at,sequence);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.account_entries FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.money_accounts FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE OR REPLACE FUNCTION app.account_create(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.money_accounts; result uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.money_accounts WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF old.request_payload<>d OR old.created_by<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF; RETURN old.id; END IF;
 INSERT INTO app.money_accounts(name,bank,reference,created_by,request_id,request_payload) VALUES(btrim(d->>'name'),btrim(d->>'bank'),coalesce(d->>'reference',''),actor,(d->>'request_id')::uuid,d) RETURNING id INTO result;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'accounts.create','money_accounts',result,d);
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION app.account_entry_post(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.account_entries; original app.account_entries; result uuid; account uuid=(d->>'account_id')::uuid;
 value numeric=(d->>'amount_mmk')::numeric; effective timestamptz=(d->>'occurred_at')::timestamptz; balance numeric; entry_kind text=d->>'kind';
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.account_entries WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF old.request_payload<>d OR old.recorded_by<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF; RETURN old.id; END IF;
 PERFORM 1 FROM app.money_accounts WHERE id=account FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Choose an account.' USING ERRCODE='23514'; END IF;
 IF effective IS NULL OR effective>now() OR nullif(btrim(d->>'description'),'') IS NULL THEN RAISE EXCEPTION 'finance: Enter a date on or before now and a description.' USING ERRCODE='23514'; END IF;
 IF entry_kind='REVERSAL' THEN
  SELECT * INTO original FROM app.account_entries WHERE id=(d->>'reverses_id')::uuid AND account_id=account;
  IF NOT FOUND OR original.kind IN ('PAYMENT','REVERSAL') OR EXISTS(SELECT 1 FROM app.account_entries WHERE reverses_id=original.id) OR effective<original.occurred_at THEN RAISE EXCEPTION 'finance: Choose an unreversed manual entry. Reverse business payments from their source.' USING ERRCODE='23514'; END IF;
  value=-original.amount_mmk;
 ELSE
  IF value IS NULL OR value='NaN' OR scale(value)>4 OR (entry_kind<>'BALANCE_ADJUSTMENT' AND value<=0) THEN RAISE EXCEPTION 'finance: Enter a valid MMK amount with up to four decimals.' USING ERRCODE='23514'; END IF;
  IF entry_kind='BALANCE_ADJUSTMENT' THEN
   -- A past observation must not silently rewrite a later reconciliation.
   IF EXISTS(SELECT 1 FROM app.account_entries WHERE account_id=account AND kind='BALANCE_ADJUSTMENT' AND occurred_at>effective) THEN RAISE EXCEPTION 'finance: Reconcile after the latest balance update.' USING ERRCODE='23514'; END IF;
   SELECT coalesce(sum(amount_mmk),0) INTO balance FROM app.account_entries WHERE account_id=account AND occurred_at<=effective;
   value=value-balance;
  ELSIF entry_kind='PERSONAL_EXPENSE' THEN value=-value;
  ELSIF entry_kind<>'EXTERNAL_DEPOSIT' THEN RAISE EXCEPTION 'finance: Invalid entry type.' USING ERRCODE='23514'; END IF;
 END IF;
 IF entry_kind<>'BALANCE_ADJUSTMENT' AND EXISTS(SELECT 1 FROM app.account_entries WHERE account_id=account AND kind='BALANCE_ADJUSTMENT' AND occurred_at>=effective) THEN RAISE EXCEPTION 'finance: This date is already reconciled. Record the correction after the latest balance update.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.account_entries(account_id,kind,amount_mmk,sender,description,occurred_at,recorded_by,request_id,request_payload,reverses_id)
 VALUES(account,entry_kind,value,coalesce(d->>'sender',''),d->>'description',effective,actor,(d->>'request_id')::uuid,d,CASE WHEN entry_kind='REVERSAL' THEN original.id END) RETURNING id INTO result;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'accounts.entry','account_entries',result,jsonb_build_object('input',d,'delta_mmk',value::text));
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION app.capture_account_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE account uuid; original uuid;
BEGIN
 IF NEW.status<>'POSTED' OR (TG_OP='UPDATE' AND OLD.status='POSTED') THEN RETURN NEW; END IF;
 account=nullif(current_setting('app.payment_account',true),'')::uuid;
 -- Expense offsets follow their original payment, including legacy unassigned payments.
 original=nullif(current_setting('app.reversal_original_payment',true),'')::uuid;
 IF original IS NOT NULL THEN
  SELECT e.account_id INTO account FROM app.account_entries e WHERE e.payment_id=original;
  IF account IS NULL THEN RETURN NEW; END IF;
 END IF;
 IF account IS NULL THEN
  IF EXISTS(SELECT 1 FROM app.money_accounts) THEN RAISE EXCEPTION 'finance: Select a bank or cash account for this payment.' USING ERRCODE='23514'; END IF;
  RETURN NEW; -- Compatibility for installations that have not configured accounts.
 END IF;
 PERFORM 1 FROM app.money_accounts WHERE id=account FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Account not found.' USING ERRCODE='23514'; END IF;
 IF NEW.paid_at>now() THEN RAISE EXCEPTION 'finance: An account payment cannot be dated in the future.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM app.account_entries WHERE account_id=account AND kind='BALANCE_ADJUSTMENT' AND occurred_at>=NEW.paid_at) THEN RAISE EXCEPTION 'finance: Payment date is already reconciled. Choose a later payment date.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.account_entries(account_id,kind,amount_mmk,description,occurred_at,recorded_by,payment_id)
 VALUES(account,'PAYMENT',CASE WHEN NEW.direction='IN' THEN NEW.amount_mmk ELSE -NEW.amount_mmk END,NEW.payment_number,NEW.paid_at,NEW.recorded_by,NEW.id);
 RETURN NEW;
END $$;
CREATE TRIGGER account_payment AFTER INSERT OR UPDATE OF status ON app.payments FOR EACH ROW EXECUTE FUNCTION app.capture_account_payment();

ALTER FUNCTION app.customer_payment(jsonb,uuid) RENAME TO customer_payment_before_accounts;
CREATE OR REPLACE FUNCTION app.customer_payment(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE result uuid; previous text=current_setting('app.payment_account',true);
BEGIN
 PERFORM set_config('app.payment_account',coalesce(d->>'account_id',''),true);
 result=app.customer_payment_before_accounts(d,actor);
 PERFORM set_config('app.payment_account',coalesce(previous,''),true);
 RETURN result;
END $$;

ALTER FUNCTION app.transport_payment(jsonb,uuid) RENAME TO transport_payment_before_accounts;
CREATE OR REPLACE FUNCTION app.transport_payment(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE result uuid; previous text=current_setting('app.payment_account',true);
BEGIN
 PERFORM set_config('app.payment_account',coalesce(d->>'account_id',''),true);
 result=app.transport_payment_before_accounts(d,actor);
 PERFORM set_config('app.payment_account',coalesce(previous,''),true);
 RETURN result;
END $$;

ALTER FUNCTION app.expense_post(jsonb,uuid) RENAME TO expense_post_before_accounts;
CREATE OR REPLACE FUNCTION app.expense_post(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE result uuid; previous text=current_setting('app.payment_account',true);
BEGIN
 PERFORM set_config('app.payment_account',coalesce(d->>'account_id',''),true);
 result=app.expense_post_before_accounts(d,actor);
 PERFORM set_config('app.payment_account',coalesce(previous,''),true);
 RETURN result;
END $$;

ALTER FUNCTION app.sales_return_post(jsonb,uuid) RENAME TO sales_return_post_before_accounts;
CREATE OR REPLACE FUNCTION app.sales_return_post(d jsonb,actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE result jsonb; previous text=current_setting('app.payment_account',true);
BEGIN
 PERFORM set_config('app.payment_account',coalesce(d->>'account_id',''),true);
 result=app.sales_return_post_before_accounts(d,actor);
 PERFORM set_config('app.payment_account',coalesce(previous,''),true);
 RETURN result;
END $$;

ALTER FUNCTION app.purchase_return_post(jsonb,uuid) RENAME TO purchase_return_post_before_accounts;
CREATE OR REPLACE FUNCTION app.purchase_return_post(d jsonb,actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE result jsonb; previous text=current_setting('app.payment_account',true);
BEGIN
 PERFORM set_config('app.payment_account',coalesce(d->>'account_id',''),true);
 result=app.purchase_return_post_before_accounts(d,actor);
 PERFORM set_config('app.payment_account',coalesce(previous,''),true);
 RETURN result;
END $$;

ALTER FUNCTION app.record_supplier_payment(uuid,uuid,jsonb) RENAME TO record_supplier_payment_before_accounts;
CREATE OR REPLACE FUNCTION app.record_supplier_payment(purchase uuid,actor uuid,data jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE result uuid; previous text=current_setting('app.payment_account',true);
BEGIN
 PERFORM set_config('app.payment_account',coalesce(data->>'account_id',''),true);
 result=app.record_supplier_payment_before_accounts(purchase,actor,data);
 PERFORM set_config('app.payment_account',coalesce(previous,''),true);
 RETURN result;
END $$;

ALTER FUNCTION app.pos_sale(jsonb,uuid,boolean,boolean,boolean) RENAME TO pos_sale_before_accounts;
CREATE OR REPLACE FUNCTION app.pos_sale(d jsonb,actor uuid,discounts boolean,below_cost boolean,preview boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE result jsonb; previous text=current_setting('app.payment_account',true);
BEGIN
 PERFORM set_config('app.payment_account',coalesce(d->>'account_id',''),true);
 result=app.pos_sale_before_accounts(d,actor,discounts,below_cost,preview);
 PERFORM set_config('app.payment_account',coalesce(previous,''),true);
 RETURN result;
END $$;

-- Carry original payment identity through reversals; readable IDs are not lineage.
DO $$ DECLARE definition text; BEGIN
 definition=pg_get_functiondef('app.expense_reverse(jsonb,uuid)'::regprocedure);
 definition=replace(definition,'  INSERT INTO app.payments(payment_number', '  PERFORM set_config(''app.reversal_original_payment'',p.id::text,true);
  INSERT INTO app.payments(payment_number');
 definition=replace(definition,'  INSERT INTO app.expense_reversal_payments', '  PERFORM set_config(''app.reversal_original_payment'','''',true);
  INSERT INTO app.expense_reversal_payments');
 EXECUTE definition;
END $$;
