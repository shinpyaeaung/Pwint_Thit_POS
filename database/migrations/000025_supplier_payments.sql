-- Reuse the immutable payments/allocation ledger; named methods retain the
-- existing accounting categories used by sales and historical payments.
CREATE TABLE app.supplier_payment_methods (
 code text PRIMARY KEY CHECK(code ~ '^[A-Z][A-Z0-9_]{0,39}$'),
 name text NOT NULL UNIQUE CHECK(length(trim(name)) BETWEEN 1 AND 100),
 category text NOT NULL CHECK(category IN ('CASH','BANK_TRANSFER','MOBILE_PAYMENT','OTHER')),
 created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO app.supplier_payment_methods VALUES
 ('CASH','Cash','CASH'),('KBZPAY','KBZPay','MOBILE_PAYMENT'),
 ('KBZ_BANKING','KBZ Banking','BANK_TRANSFER'),('YOMA_BANKING','Yoma Banking','BANK_TRANSFER'),
 ('BANK_TRANSFER','Bank Transfer','BANK_TRANSFER'),('OTHER','Other','OTHER');
ALTER TABLE app.payments ADD COLUMN supplier_method_code text REFERENCES app.supplier_payment_methods(code),
 ADD COLUMN method_name_snapshot text, ADD COLUMN bank_account text;
CREATE TABLE app.supplier_payment_requests (
 request_id uuid PRIMARY KEY, purchase_id uuid NOT NULL REFERENCES app.purchases(id),
 payment_id uuid NOT NULL UNIQUE REFERENCES app.payments(id), payload jsonb NOT NULL
);
CREATE TRIGGER supplier_payment_requests_immutable BEFORE UPDATE OR DELETE ON app.supplier_payment_requests
 FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();

CREATE FUNCTION app.record_supplier_payment(purchase uuid, actor uuid, data jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE doc app.purchases%ROWTYPE; method app.supplier_payment_methods%ROWTYPE;
 prior app.supplier_payment_requests%ROWTYPE; payment uuid; balance numeric;
 amount numeric := (data->>'amount')::numeric; rate numeric; currency text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(data->>'request_id',0));
 SELECT * INTO prior FROM app.supplier_payment_requests WHERE request_id=(data->>'request_id')::uuid;
 IF FOUND THEN
  IF prior.purchase_id<>purchase OR prior.payload<>data THEN RAISE EXCEPTION 'This payment request was already used with different details.' USING ERRCODE='23514'; END IF;
  RETURN prior.payment_id;
 END IF;
 SELECT * INTO doc FROM app.purchases WHERE id=purchase FOR UPDATE;
 IF NOT FOUND OR doc.status<>'POSTED' THEN RAISE EXCEPTION 'Choose a posted purchase.' USING ERRCODE='23514'; END IF;
 IF (data->>'paid_at')::timestamptz<doc.purchased_at THEN RAISE EXCEPTION 'Payment date cannot precede purchase date.' USING ERRCODE='23514'; END IF;
 SELECT * INTO method FROM app.supplier_payment_methods WHERE code=data->>'method_code';
 IF NOT FOUND THEN RAISE EXCEPTION 'Choose a payment method.' USING ERRCODE='23514'; END IF;
 SELECT outstanding_original INTO balance FROM app.supplier_payables WHERE purchase_id=purchase;
 IF amount<=0 OR amount>balance THEN RAISE EXCEPTION 'Payment amount cannot exceed the remaining balance.' USING ERRCODE='23514'; END IF;
 -- Payments settle in the invoice currency at its immutable transaction rate.
 currency:=doc.currency_code; rate:=doc.mmk_per_unit;
 INSERT INTO app.payments(payment_number,direction,method,supplier_method_code,method_name_snapshot,bank_account,currency_code,amount_original,mmk_per_unit,supplier_id,paid_at,reference_number,notes,recorded_by)
 VALUES('','OUT',method.category,method.code,method.name,NULLIF(data->>'bank_account',''),currency,amount,rate,doc.supplier_id,(data->>'paid_at')::timestamptz,NULLIF(data->>'reference_number',''),NULLIF(data->>'notes',''),actor) RETURNING id INTO payment;
 INSERT INTO app.payment_allocations(payment_id,purchase_id,settlement_mmk,applied_mmk,applied_original)
 VALUES(payment,purchase,round(amount*rate,4),round(amount*rate,4),amount);
 UPDATE app.payments SET status='POSTED',posted_at=clock_timestamp() WHERE id=payment;
 INSERT INTO app.supplier_payment_requests VALUES((data->>'request_id')::uuid,purchase,payment,data);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value)
 VALUES(actor,'supplier_payments.create','payments',payment,data||jsonb_build_object('purchase_id',purchase,'currency_code',currency,'mmk_per_unit',rate::text));
 RETURN payment;
END $$;
