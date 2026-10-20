-- Account metadata can change; account identity and all ledger rows stay immutable.
ALTER TABLE app.money_accounts ADD COLUMN is_active boolean NOT NULL DEFAULT true,
 ADD COLUMN version integer NOT NULL DEFAULT 1;
CREATE TABLE app.account_changes (
 request_id uuid PRIMARY KEY, account_id uuid NOT NULL REFERENCES app.money_accounts(id),
 actor_id uuid NOT NULL REFERENCES app.users(id), payload jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.account_changes FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
DROP TRIGGER immutable ON app.money_accounts;
CREATE FUNCTION app.guard_account_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'finance: Archive accounts to preserve their history.' USING ERRCODE='23514'; END IF;
 IF (to_jsonb(NEW)-ARRAY['name','bank','reference','is_active','version']) IS DISTINCT FROM
    (to_jsonb(OLD)-ARRAY['name','bank','reference','is_active','version']) OR NEW.version<>OLD.version+1 THEN
  RAISE EXCEPTION 'finance: Account identity is immutable.' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable BEFORE UPDATE OR DELETE ON app.money_accounts FOR EACH ROW EXECUTE FUNCTION app.guard_account_identity();
CREATE FUNCTION app.account_update(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE previous app.account_changes; old app.money_accounts; updated app.money_accounts;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO previous FROM app.account_changes WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
  IF previous.payload<>d OR previous.actor_id<>actor THEN RAISE EXCEPTION 'finance: Request already used.' USING ERRCODE='23514'; END IF;
  RETURN previous.account_id;
 END IF;
 SELECT * INTO old FROM app.money_accounts WHERE id=(d->>'account_id')::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'finance: Account not found.' USING ERRCODE='23514'; END IF;
 IF old.version<>(d->>'version')::integer THEN RAISE EXCEPTION 'finance: Account changed. Reload before editing.' USING ERRCODE='23514'; END IF;
 UPDATE app.money_accounts SET name=btrim(d->>'name'),bank=btrim(d->>'bank'),reference=btrim(d->>'reference'),
  is_active=(d->>'is_active')::boolean,version=version+1 WHERE id=old.id RETURNING * INTO updated;
 INSERT INTO app.account_changes(request_id,account_id,actor_id,payload) VALUES((d->>'request_id')::uuid,old.id,actor,d);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value)
 VALUES(actor,CASE WHEN old.is_active AND NOT updated.is_active THEN 'accounts.archive'
                   WHEN NOT old.is_active AND updated.is_active THEN 'accounts.restore' ELSE 'accounts.update' END,
        'money_accounts',old.id,to_jsonb(old),to_jsonb(updated));
 RETURN old.id;
END $$;
-- Serialize against metadata changes and reject new activity on archived accounts.
-- Source-linked payment reversals must still be able to correct their original ledger.
CREATE FUNCTION app.guard_active_account_entry() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE active boolean;
BEGIN
 SELECT is_active INTO active FROM app.money_accounts WHERE id=NEW.account_id FOR UPDATE;
 IF NOT active AND NOT (NEW.kind='PAYMENT' AND nullif(current_setting('app.reversal_original_payment',true),'') IS NOT NULL) THEN
  RAISE EXCEPTION 'finance: This account is archived. Restore it before recording transactions.' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER active_account BEFORE INSERT ON app.account_entries FOR EACH ROW EXECUTE FUNCTION app.guard_active_account_entry();
