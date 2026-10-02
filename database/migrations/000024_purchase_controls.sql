-- A purchase can be reversed before any downstream stock or payment activity.
-- Original purchase amounts/items stay immutable; payable views already exclude reversals.
CREATE TABLE app.purchase_reversals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), purchase_id uuid NOT NULL UNIQUE REFERENCES app.purchases(id),
 recorded_by uuid NOT NULL REFERENCES app.users(id), reason text NOT NULL CHECK(btrim(reason)<>''),
 reversed_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER purchase_reversal_immutable BEFORE UPDATE OR DELETE ON app.purchase_reversals FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE FUNCTION app.reverse_unallocated_purchase(purchase uuid, actor uuid, why text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p app.purchases;
BEGIN
 SELECT * INTO p FROM app.purchases WHERE id=purchase FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase not found.' USING ERRCODE='23514'; END IF;
 IF p.status<>'POSTED' THEN RAISE EXCEPTION 'Only a posted purchase can be reversed.' USING ERRCODE='23514'; END IF;
 PERFORM id FROM app.purchase_items WHERE purchase_id=p.id ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM app.shipment_items si JOIN app.purchase_items pi ON pi.id=si.purchase_item_id JOIN app.shipments sh ON sh.id=si.shipment_id WHERE pi.purchase_id=p.id AND sh.status<>'CANCELLED')
 OR EXISTS(SELECT 1 FROM app.payment_allocations WHERE purchase_id=p.id)
 OR EXISTS(SELECT 1 FROM app.purchase_returns WHERE purchase_id=p.id) THEN
  RAISE EXCEPTION 'This purchase has shipment, payment or return history. Use its linked correction controls.' USING ERRCODE='23514';
 END IF;
 IF btrim(why)='' OR length(why)>1000 THEN RAISE EXCEPTION 'Enter a reversal reason.' USING ERRCODE='23514';END IF;
 UPDATE app.purchases SET status='REVERSED' WHERE id=p.id;
 INSERT INTO app.purchase_reversals(purchase_id,recorded_by,reason) VALUES(p.id,actor,why);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value,reason)
 VALUES(actor,'purchases.reverse','purchases',p.id,to_jsonb(p),jsonb_build_object('status','REVERSED'),why);
END $$;
