-- Explicit account erasure is the only exception to append-only financial history.
CREATE TABLE app.account_deletions (
 request_id uuid PRIMARY KEY, account_id uuid NOT NULL UNIQUE, actor_id uuid NOT NULL REFERENCES app.users(id),
 payload jsonb NOT NULL, summary jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.account_deletions FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE TABLE app.deleted_finance_requests(request_id uuid PRIMARY KEY);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.deleted_finance_requests FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
-- Exact row fingerprints, local to the executing transaction; never disable triggers.
CREATE TABLE app.account_delete_scope(tx bigint NOT NULL, relation text NOT NULL, fingerprint text NOT NULL, PRIMARY KEY(tx,relation,fingerprint));
CREATE FUNCTION app.account_delete_allowed(relation text, row_data jsonb) RETURNS boolean LANGUAGE sql VOLATILE AS $$
 SELECT EXISTS(SELECT 1 FROM app.account_delete_scope s WHERE s.tx=txid_current() AND s.relation=$1 AND s.fingerprint=md5($2::text))
$$;
CREATE OR REPLACE FUNCTION app.deny_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' AND app.account_delete_allowed(TG_TABLE_NAME,to_jsonb(OLD)) THEN RETURN OLD; END IF; RAISE EXCEPTION '% is append-only; use a new record or reversal',TG_TABLE_NAME USING ERRCODE='23514'; END $$;
CREATE OR REPLACE FUNCTION app.protect_posted_document() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' AND app.account_delete_allowed(TG_TABLE_NAME,to_jsonb(OLD)) THEN RETURN OLD; END IF;
 IF OLD.posted_at IS NOT NULL THEN
  IF TG_OP='UPDATE' AND OLD.status='POSTED' AND NEW.status='REVERSED'
   AND (to_jsonb(NEW)-'status'-'updated_at')=(to_jsonb(OLD)-'status'-'updated_at') THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'posted % must be reversed, not edited or deleted',TG_TABLE_NAME USING ERRCODE='23514';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION app.protect_document_item() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_id uuid; locked_at timestamptz; row_data jsonb;
BEGIN
 IF TG_OP='DELETE' AND app.account_delete_allowed(TG_TABLE_NAME,to_jsonb(OLD)) THEN RETURN OLD; END IF;
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
CREATE OR REPLACE FUNCTION app.guard_account_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' AND app.account_delete_allowed(TG_TABLE_NAME,to_jsonb(OLD)) THEN RETURN OLD; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'finance: Archive accounts to preserve their history.' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['name','bank','reference','is_active','version','account_type','holder']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['name','bank','reference','is_active','version','account_type','holder']) OR NEW.version<>OLD.version+1 THEN
  RAISE EXCEPTION 'finance: Account identity is immutable.' USING ERRCODE='23514'; END IF;
 IF OLD.account_type<>'UNCLASSIFIED' AND NEW.account_type<>OLD.account_type AND EXISTS(SELECT 1 FROM app.account_entries WHERE account_id=OLD.id) THEN
  RAISE EXCEPTION 'finance: An account with history cannot change between bank and cash. Create a separate account.' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE FUNCTION app.reject_deleted_finance_request() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM app.deleted_finance_requests WHERE request_id=NEW.request_id) THEN
  RAISE EXCEPTION 'finance: This request belongs to a permanently deleted account. Start a new transaction.' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['money_accounts','account_entries','account_changes','payments','person_transactions','supplier_payment_requests','transport_payment_requests','creditor_repayments','creditor_repayment_reversals'] LOOP
 EXECUTE format('CREATE TRIGGER deleted_request BEFORE INSERT ON app.%I FOR EACH ROW EXECUTE FUNCTION app.reject_deleted_finance_request()',t);
 END LOOP;
END $$;
CREATE FUNCTION app.account_delete_payments(account uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
 WITH RECURSIVE edges(a,b) AS (
 SELECT id,reverses_payment_id FROM app.payments WHERE reverses_payment_id IS NOT NULL
 UNION SELECT original_payment_id,offset_payment_id FROM app.expense_reversal_payments
 UNION SELECT original_payment_id,payment_id FROM app.creditor_repayment_reversals
 ), links(a,b) AS(SELECT a,b FROM edges UNION SELECT b,a FROM edges), selected(id) AS (
 SELECT payment_id FROM app.account_entries WHERE account_id=$1 AND payment_id IS NOT NULL
 UNION SELECT l.b FROM links l JOIN selected s ON l.a=s.id
 ) SELECT id FROM selected
$$;
CREATE FUNCTION app.account_delete_preview(account uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE result jsonb;
BEGIN
 SELECT jsonb_build_object('name',a.name,'account_id',a.id,'version',a.version,
 'balance_mmk',coalesce((SELECT sum(amount_mmk) FROM app.account_entries WHERE account_id=a.id),0)::text,
 'entries',(SELECT count(*) FROM app.account_entries WHERE account_id=a.id),
 'payments',(SELECT count(*) FROM app.account_delete_payments(a.id)),
 'personal_transactions',(SELECT count(*) FROM app.person_transactions WHERE account_id=a.id),
 'allocations',(SELECT count(*) FROM app.payment_allocations WHERE payment_id IN (SELECT app.account_delete_payments(a.id))),
 'fingerprint',md5(to_jsonb(a)::text||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM app.account_entries WHERE account_id=a.id),'')||coalesce((SELECT string_agg(p::text,',' ORDER BY p) FROM app.account_delete_payments(a.id) p),''))) INTO result
 FROM app.money_accounts a WHERE a.id=account;
 IF result IS NULL THEN RAISE EXCEPTION 'finance: Account not found.' USING ERRCODE='23514'; END IF;
 RETURN result;
END $$;
CREATE FUNCTION app.account_delete(d jsonb, actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE aid uuid=(d->>'account_id')::uuid; summary jsonb; previous app.account_deletions; payments uuid[]; persons uuid[]; entries uuid[]; t text; predicate text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.users WHERE id=actor AND role_code='SUPER_ADMIN') THEN
 RAISE EXCEPTION 'finance: Only Super Admin can permanently delete accounts.' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO previous FROM app.account_deletions WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
 IF previous.payload<>d OR previous.actor_id<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF;
 RETURN previous.account_id;
 END IF;
 -- Serialize erasure against posting/reversal, including linked creditor entries.
 LOCK TABLE app.money_accounts,app.payments,app.account_entries,app.person_transactions,app.creditors,
 app.payment_allocations,app.account_changes,app.supplier_payment_requests,app.transport_payment_requests,
 app.creditor_repayments,app.creditor_repayment_reversals,app.expense_reversal_payments IN EXCLUSIVE MODE;
 summary=app.account_delete_preview(aid);
 IF d->>'fingerprint' IS DISTINCT FROM summary->>'fingerprint' THEN RAISE EXCEPTION 'finance: Account history changed. Close and review deletion again.' USING ERRCODE='23514'; END IF;
 IF d->>'confirmation' IS DISTINCT FROM summary->>'name' OR length(btrim(coalesce(d->>'reason','')))=0 THEN
 RAISE EXCEPTION 'finance: Enter the exact account name and a deletion reason.' USING ERRCODE='23514'; END IF;
 SELECT coalesce(array_agg(p),'{}') INTO payments FROM app.account_delete_payments(aid) p;
 SELECT coalesce(array_agg(id),'{}') INTO persons FROM app.person_transactions WHERE account_id=aid;
 SELECT coalesce(array_agg(id),'{}') INTO entries FROM app.account_entries WHERE account_id=aid OR payment_id=ANY(payments) OR person_transaction_id=ANY(persons);
 IF EXISTS(SELECT 1 FROM app.account_entries WHERE id=ANY(entries) AND account_id<>aid) THEN
 RAISE EXCEPTION 'finance: A linked reversal uses another account. Its history must be resolved before deleting this account.' USING ERRCODE='23514'; END IF;
 -- Never erase other accounts to hide an invalid remaining loan balance.
 IF EXISTS(SELECT 1 FROM app.account_entries WHERE creditor_id IN(SELECT creditor_id FROM app.account_entries WHERE id=ANY(entries)) AND NOT(id=ANY(entries)) GROUP BY creditor_id,debt_side HAVING sum(amount_mmk)<0) THEN
 RAISE EXCEPTION 'finance: Deletion would leave repayments without their loan. Reverse the related repayments first.' USING ERRCODE='23514'; END IF;
 FOREACH t IN ARRAY ARRAY['account_entries','account_changes','person_transactions','creditor_repayment_reversals','creditor_repayments','supplier_payment_requests','transport_payment_requests','expense_reversal_payments','payment_allocations','attachment_links','approvals','payments','money_accounts'] LOOP
 predicate=CASE t
 WHEN 'money_accounts' THEN 'id=$1'
 WHEN 'account_changes' THEN 'account_id=$1'
 WHEN 'account_entries' THEN 'id=ANY($4)'
 WHEN 'person_transactions' THEN 'id=ANY($3)'
 WHEN 'payments' THEN 'id=ANY($2)'
 WHEN 'expense_reversal_payments' THEN 'original_payment_id=ANY($2) OR offset_payment_id=ANY($2)'
 WHEN 'creditor_repayment_reversals' THEN 'original_payment_id=ANY($2) OR payment_id=ANY($2)'
 ELSE 'payment_id=ANY($2)' END;
 EXECUTE format('INSERT INTO app.account_delete_scope SELECT txid_current(),%L,md5(to_jsonb(r)::text) FROM app.%I r WHERE %s',t,t,predicate) USING aid,payments,persons,entries;
 IF t IN ('money_accounts','account_entries','account_changes','person_transactions','payments','creditor_repayment_reversals','creditor_repayments','supplier_payment_requests','transport_payment_requests') THEN
 EXECUTE format('INSERT INTO app.deleted_finance_requests SELECT request_id FROM app.%I WHERE (%s) AND request_id IS NOT NULL ON CONFLICT DO NOTHING',t,predicate) USING aid,payments,persons,entries;
 END IF;
 EXECUTE format('DELETE FROM app.%I WHERE %s',t,predicate) USING aid,payments,persons,entries;
 END LOOP;
 INSERT INTO app.account_deletions VALUES((d->>'request_id')::uuid,aid,actor,d,summary,now());
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value,reason)
 VALUES(actor,'accounts.delete','money_accounts',aid,summary,d->>'reason');
 DELETE FROM app.account_delete_scope WHERE tx=txid_current();
 RETURN aid;
END $$;
