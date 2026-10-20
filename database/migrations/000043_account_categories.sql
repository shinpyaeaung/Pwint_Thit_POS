-- Separate business assets from personal borrowing and lending without rewriting ledger history.
ALTER TABLE app.money_accounts ADD COLUMN account_type text NOT NULL DEFAULT 'UNCLASSIFIED' CHECK(account_type IN ('BANK','CASH','UNCLASSIFIED')),
 ADD COLUMN holder text NOT NULL DEFAULT '' CHECK(length(holder)<=100);
DROP TRIGGER immutable ON app.money_accounts;
UPDATE app.money_accounts SET account_type=CASE WHEN lower(btrim(bank))='cash' THEN 'CASH' WHEN btrim(bank)<>'' THEN 'BANK' ELSE 'UNCLASSIFIED' END;
CREATE OR REPLACE FUNCTION app.guard_account_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'finance: Archive accounts to preserve their history.' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['name','bank','reference','is_active','version','account_type','holder']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['name','bank','reference','is_active','version','account_type','holder']) OR NEW.version<>OLD.version+1 THEN
  RAISE EXCEPTION 'finance: Account identity is immutable.' USING ERRCODE='23514'; END IF;
 IF OLD.account_type<>'UNCLASSIFIED' AND NEW.account_type<>OLD.account_type AND EXISTS(SELECT 1 FROM app.account_entries WHERE account_id=OLD.id) THEN
  RAISE EXCEPTION 'finance: An account with history cannot change between bank and cash. Create a separate account.' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.money_accounts FOR EACH ROW EXECUTE FUNCTION app.guard_account_identity();
CREATE OR REPLACE FUNCTION app.account_create(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.money_accounts; result uuid; typ text=coalesce(nullif(d->>'account_type',''),CASE WHEN lower(coalesce(d->>'bank','')) IN ('','cash') THEN 'CASH' ELSE 'BANK' END); opening numeric=coalesce(nullif(d->>'opening_balance',''),'0')::numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.money_accounts WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF old.request_payload<>d OR old.created_by<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF; RETURN old.id; END IF;
 IF typ NOT IN ('BANK','CASH') OR opening<0 OR opening='NaN' OR scale(opening)>4 THEN RAISE EXCEPTION 'finance: Choose bank or cash and a nonnegative opening balance.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.money_accounts(name,bank,reference,holder,account_type,created_by,request_id,request_payload)
 VALUES(btrim(d->>'name'),CASE WHEN typ='BANK' THEN btrim(d->>'bank') ELSE '' END,CASE WHEN typ='BANK' THEN coalesce(d->>'reference','') ELSE '' END,coalesce(d->>'holder',''),typ,actor,(d->>'request_id')::uuid,d) RETURNING id INTO result;
 IF opening>0 THEN
  INSERT INTO app.account_entries(account_id,kind,amount_mmk,sender,description,occurred_at,recorded_by)
  VALUES(result,'EXTERNAL_DEPOSIT',opening,'Opening balance','Opening balance',now(),actor);
 END IF;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'accounts.create','money_accounts',result,d);
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION app.account_update(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE previous app.account_changes; old app.money_accounts; updated app.money_accounts;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO previous FROM app.account_changes WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF previous.payload<>d OR previous.actor_id<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF; RETURN previous.account_id; END IF;
 SELECT * INTO old FROM app.money_accounts WHERE id=(d->>'account_id')::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Account not found.' USING ERRCODE='23514'; END IF;
 IF old.version<>(d->>'version')::integer THEN RAISE EXCEPTION 'finance: Account changed. Reload before editing.' USING ERRCODE='23514'; END IF;
 UPDATE app.money_accounts SET name=btrim(d->>'name'),bank=btrim(d->>'bank'),reference=btrim(d->>'reference'),
 holder=coalesce(d->>'holder',old.holder),account_type=coalesce(nullif(d->>'account_type',''),old.account_type),is_active=(d->>'is_active')::boolean,version=version+1 WHERE id=old.id RETURNING * INTO updated;
 INSERT INTO app.account_changes VALUES((d->>'request_id')::uuid,old.id,actor,d,now());
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value) VALUES(actor,CASE WHEN old.is_active AND NOT updated.is_active THEN 'accounts.archive' WHEN NOT old.is_active AND updated.is_active THEN 'accounts.restore' ELSE 'accounts.update' END,'money_accounts',old.id,to_jsonb(old),to_jsonb(updated));
 RETURN old.id;
END $$;
ALTER TABLE app.account_entries ADD COLUMN debt_side text NOT NULL DEFAULT 'PAYABLE' CHECK(debt_side IN ('PAYABLE','RECEIVABLE'));
CREATE TABLE app.person_transactions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL UNIQUE, creditor_id uuid NOT NULL REFERENCES app.creditors(id), account_id uuid NOT NULL REFERENCES app.money_accounts(id),
 kind text NOT NULL CHECK(kind IN ('BORROW','LEND','COLLECT','GIFT_RECEIVED','GIFT_GIVEN','REVERSAL')), reverses_id uuid UNIQUE REFERENCES app.person_transactions(id),
 actor_id uuid NOT NULL REFERENCES app.users(id),payload jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.person_transactions FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
ALTER TABLE app.account_entries ADD COLUMN person_transaction_id uuid REFERENCES app.person_transactions(id);
ALTER TABLE app.account_entries DROP CONSTRAINT account_entries_kind_check;
ALTER TABLE app.account_entries ADD CHECK(kind IN ('PAYMENT','EXTERNAL_DEPOSIT','PERSONAL_EXPENSE','BALANCE_ADJUSTMENT','REVERSAL','PERSON_TRANSACTION'));
CREATE UNIQUE INDEX person_cash_once ON app.account_entries(person_transaction_id) WHERE account_id IS NOT NULL;
CREATE UNIQUE INDEX person_debt_once ON app.account_entries(person_transaction_id) WHERE creditor_id IS NOT NULL;
-- Keep lending and borrowing independent even for the same person.
DO $$ DECLARE def text; BEGIN
 def=pg_get_functiondef('app.guard_active_account_entry()'::regprocedure);
 def=replace(def,'WHERE creditor_id=NEW.creditor_id','WHERE creditor_id=NEW.creditor_id AND debt_side=NEW.debt_side'); EXECUTE def;
 def=pg_get_functiondef('app.creditor_repay(jsonb,uuid)'::regprocedure);
 def=replace(def,'WHERE creditor_id=creditor AND occurred_at','WHERE creditor_id=creditor AND debt_side=''PAYABLE'' AND occurred_at'); EXECUTE def;
END $$;
-- The database also validates the account category; filtering alone is not sufficient.
CREATE FUNCTION app.validate_payment_account_category() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE typ text; meth text;
BEGIN
 IF NEW.account_id IS NULL OR NEW.payment_id IS NULL OR nullif(current_setting('app.reversal_original_payment',true),'') IS NOT NULL THEN RETURN NEW; END IF;
 SELECT account_type INTO typ FROM app.money_accounts WHERE id=NEW.account_id;
 SELECT method INTO meth FROM app.payments WHERE id=NEW.payment_id;
 IF typ='UNCLASSIFIED' OR (meth='CASH' AND typ<>'CASH') OR (meth IN ('BANK_TRANSFER','MOBILE_PAYMENT') AND typ<>'BANK') THEN
  RAISE EXCEPTION 'finance: Choose a cash account for cash or a bank account for electronic payment. Classify legacy accounts first.' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER payment_category BEFORE INSERT ON app.account_entries FOR EACH ROW EXECUTE FUNCTION app.validate_payment_account_category();
CREATE FUNCTION app.person_transaction(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE prior app.person_transactions; source app.person_transactions; result uuid; person uuid=(d->>'creditor_id')::uuid; account uuid=(d->>'account_id')::uuid;
 kind text=d->>'kind'; value numeric=(d->>'amount_mmk')::numeric; effective timestamptz=(d->>'occurred_at')::timestamptz; cash numeric; debt numeric=0; side text='PAYABLE'; person_name text; account_name text; method text; original_entry app.account_entries;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO prior FROM app.person_transactions WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF prior.payload<>d OR prior.actor_id<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF; RETURN prior.id; END IF;
 IF kind='REVERSAL' THEN
  SELECT * INTO source FROM app.person_transactions WHERE id=(d->>'reverses_id')::uuid;
  IF NOT FOUND OR source.creditor_id<>person OR source.kind='REVERSAL' OR EXISTS(SELECT 1 FROM app.person_transactions WHERE reverses_id=source.id) THEN RAISE EXCEPTION 'finance: Choose an unreversed personal transaction.' USING ERRCODE='23514'; END IF;
  person=source.creditor_id;account=source.account_id;
 END IF;
 SELECT name INTO person_name FROM app.creditors WHERE id=person FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Choose a person.' USING ERRCODE='23514'; END IF;
 SELECT name,CASE account_type WHEN 'CASH' THEN 'CASH' ELSE 'BANK_TRANSFER' END INTO account_name,method FROM app.money_accounts WHERE id=account AND account_type<>'UNCLASSIFIED' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Choose a classified bank or cash account.' USING ERRCODE='23514'; END IF;
 IF effective IS NULL OR effective>now() OR nullif(btrim(d->>'description'),'') IS NULL THEN RAISE EXCEPTION 'finance: Enter a valid date and description.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM app.account_entries e WHERE e.account_id=account AND e.kind='BALANCE_ADJUSTMENT' AND e.occurred_at>=effective) THEN RAISE EXCEPTION 'finance: This date is already reconciled.' USING ERRCODE='23514'; END IF;
 IF kind='REVERSAL' THEN
  SELECT * INTO original_entry FROM app.account_entries WHERE person_transaction_id=source.id AND account_id IS NOT NULL;
  IF effective<original_entry.occurred_at THEN RAISE EXCEPTION 'finance: Reverse after the original date.' USING ERRCODE='23514'; END IF;
  cash=-original_entry.amount_mmk;
  SELECT -amount_mmk,debt_side INTO debt,side FROM app.account_entries WHERE person_transaction_id=source.id AND creditor_id IS NOT NULL;
 ELSE
  IF value IS NULL OR value<=0 OR value='NaN' OR scale(value)>4 THEN RAISE EXCEPTION 'finance: Enter a positive amount with up to four decimals.' USING ERRCODE='23514'; END IF;
  CASE kind
   WHEN 'BORROW' THEN cash=value;debt=value;
   WHEN 'LEND' THEN cash=-value;debt=value;side='RECEIVABLE';
   WHEN 'COLLECT' THEN cash=value;debt=-value;side='RECEIVABLE';
   WHEN 'GIFT_RECEIVED' THEN cash=value;
   WHEN 'GIFT_GIVEN' THEN cash=-value;
   ELSE RAISE EXCEPTION 'finance: Invalid personal transaction.' USING ERRCODE='23514';
  END CASE;
 END IF;
 INSERT INTO app.person_transactions(request_id,creditor_id,account_id,kind,reverses_id,actor_id,payload) VALUES((d->>'request_id')::uuid,person,account,kind,source.id,actor,d) RETURNING id INTO result;
 INSERT INTO app.account_entries(account_id,kind,amount_mmk,description,occurred_at,recorded_by,person_transaction_id,payer,payee,method,reference)
 VALUES(account,'PERSON_TRANSACTION',cash,d->>'description',effective,actor,result,CASE WHEN cash>0 THEN person_name ELSE account_name END,CASE WHEN cash>0 THEN account_name ELSE person_name END,method,coalesce(d->>'reference',''));
 INSERT INTO app.account_entries(creditor_id,kind,amount_mmk,debt_side,description,occurred_at,recorded_by,person_transaction_id,payer,payee,method,reference)
 VALUES(person,'PERSON_TRANSACTION',debt,side,d->>'description',effective,actor,result,CASE WHEN cash>0 THEN person_name ELSE account_name END,CASE WHEN cash>0 THEN account_name ELSE person_name END,method,coalesce(d->>'reference',''));
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'accounts.person_transaction','person_transactions',result,d);
 RETURN result;
END $$;
-- Manual reversals must not reverse just the cash half of a loan or gift.
DO $$ DECLARE def text; BEGIN
 def=pg_get_functiondef('app.account_entry_post(jsonb,uuid)'::regprocedure);
 def=replace(def,'original.kind IN (''PAYMENT'',''REVERSAL'')','original.kind IN (''PAYMENT'',''REVERSAL'',''PERSON_TRANSACTION'')'); EXECUTE def;
END $$;
DO $$ DECLARE def text; needle text='result=app.record_supplier_payment_before_accounts(purchase,actor,data);'; BEGIN
 def=pg_get_functiondef('app.record_supplier_payment(uuid,uuid,jsonb)'::regprocedure);
 def=replace(def,needle,'PERFORM set_config(''app.cash_recipient'',coalesce(data->>''cash_recipient'',''''),true); '||needle||' PERFORM set_config(''app.cash_recipient'','''',true);'); EXECUTE def;
 def=pg_get_functiondef('app.capture_account_payment()'::regprocedure);
 def=replace(def,'IF creditor IS NOT NULL THEN', 'IF NEW.method=''CASH'' AND NEW.direction=''OUT'' AND nullif(current_setting(''app.cash_recipient'',true),'''') IS NOT NULL THEN payee_name=current_setting(''app.cash_recipient'',true); END IF; IF creditor IS NOT NULL THEN'); EXECUTE def;
END $$;
