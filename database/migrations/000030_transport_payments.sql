CREATE TABLE app.transport_payment_requests (
 request_id uuid PRIMARY KEY, payment_id uuid NOT NULL UNIQUE REFERENCES app.payments(id),
 actor_id uuid NOT NULL REFERENCES app.users(id), payload jsonb NOT NULL
);
CREATE TRIGGER transport_payment_requests_immutable BEFORE UPDATE OR DELETE ON app.transport_payment_requests FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE VIEW app.transport_balances AS
 SELECT t.id,'TRANSPORT'::text AS kind,t.shipment_id,s.shipment_number,s.status AS shipment_status,t.transportation_number AS reference,t.provider_name AS payee,
 'MMK'::text AS currency_code,1::numeric AS rate,t.total_mmk AS total,
 coalesce((SELECT sum(a.applied_original) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.transportation_stage_id=t.id AND p.status='POSTED' AND p.direction='OUT'),0) AS paid
 FROM app.transportation_stages t JOIN app.shipments s ON s.id=t.shipment_id
 UNION ALL
 SELECT e.id,'ADDITIONAL_COST',e.shipment_id,s.shipment_number,s.status,e.category,e.description,e.currency_code,e.mmk_per_unit,e.amount_original,
 coalesce((SELECT sum(a.applied_original) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.shipment_expense_id=e.id AND p.status='POSTED' AND p.direction='OUT'),0)
 FROM app.shipment_expenses e JOIN app.shipments s ON s.id=e.shipment_id WHERE e.voided_at IS NULL;
CREATE FUNCTION app.transport_payment(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE prior app.transport_payment_requests; target app.transport_balances; parent uuid; payment uuid;
 method app.supplier_payment_methods; amount numeric=(d->>'amount')::numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO prior FROM app.transport_payment_requests WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
  IF prior.actor_id<>actor OR prior.payload<>d THEN RAISE EXCEPTION 'pos: Payment request already used with different details.' USING ERRCODE='23514'; END IF;
  RETURN prior.payment_id;
 END IF;
 SELECT shipment_id INTO parent FROM app.transport_balances WHERE id=(d->>'target_id')::uuid AND kind=d->>'kind';
 IF parent IS NULL THEN RAISE EXCEPTION 'pos: Choose an existing transportation charge.' USING ERRCODE='23514'; END IF;
 -- Same parent lock as cost editing/voiding, plus serialization of all payments.
 PERFORM id FROM app.shipments WHERE id=parent FOR UPDATE;
 SELECT * INTO target FROM app.transport_balances WHERE id=(d->>'target_id')::uuid AND kind=d->>'kind';
 IF NOT FOUND OR amount IS NULL OR amount<=0 OR amount='NaN' OR amount>target.total-target.paid THEN RAISE EXCEPTION 'pos: Payment amount cannot exceed the remaining balance.' USING ERRCODE='23514'; END IF;
 SELECT * INTO method FROM app.supplier_payment_methods WHERE code=d->>'method_code';
 IF NOT FOUND THEN RAISE EXCEPTION 'pos: Choose a payment method.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.payments(payment_number,direction,method,supplier_method_code,method_name_snapshot,bank_account,currency_code,amount_original,mmk_per_unit,paid_at,reference_number,notes,recorded_by)
 VALUES('','OUT',method.category,method.code,method.name,nullif(d->>'bank_account',''),target.currency_code,amount,target.rate,(d->>'paid_at')::timestamptz,nullif(d->>'reference_number',''),nullif(d->>'notes',''),actor) RETURNING id INTO payment;
 INSERT INTO app.payment_allocations(payment_id,transportation_stage_id,shipment_expense_id,settlement_mmk,applied_mmk,applied_original)
 VALUES(payment,CASE WHEN target.kind='TRANSPORT' THEN target.id END,CASE WHEN target.kind='ADDITIONAL_COST' THEN target.id END,round(amount*target.rate,4),round(amount*target.rate,4),amount);
 UPDATE app.payments SET status='POSTED',posted_at=clock_timestamp() WHERE id=payment;
 INSERT INTO app.transport_payment_requests VALUES((d->>'request_id')::uuid,payment,actor,d);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'transport_payments.create','payments',payment,d||jsonb_build_object('payee',target.payee,'shipment_id',parent));
 RETURN payment;
END $$;
