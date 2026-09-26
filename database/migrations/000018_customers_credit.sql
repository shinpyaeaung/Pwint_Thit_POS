ALTER TABLE app.customers ADD COLUMN version bigint NOT NULL DEFAULT 1;
CREATE INDEX customers_search ON app.customers(lower(name));
CREATE TABLE app.customer_prices (
 customer_id uuid NOT NULL REFERENCES app.customers(id), product_id uuid NOT NULL,
 unit_code text NOT NULL, price_mmk numeric(20,4) NOT NULL CHECK(price_mmk>=0 AND price_mmk<>'NaN'),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(customer_id,product_id,unit_code),
 FOREIGN KEY(product_id,unit_code) REFERENCES app.product_units(product_id,unit_code)
);
CREATE INDEX customer_prices_product ON app.customer_prices(product_id,unit_code);
CREATE TRIGGER z_touch_updated_at BEFORE UPDATE ON app.customer_prices FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
ALTER TABLE app.payments ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.payments ADD COLUMN request_payload jsonb;

CREATE FUNCTION app.customer_save(d jsonb, actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.customers; result uuid=nullif(d->>'id','')::uuid;
BEGIN
 IF result IS NULL THEN
  INSERT INTO app.customers(code,name,business_name,phone,address,customer_type,credit_limit_mmk,notes,is_active)
  VALUES(d->>'code',d->>'name',d->>'business_name',d->>'phone',d->>'address',d->>'customer_type',(d->>'credit_limit_mmk')::numeric,d->>'notes',(d->>'is_active')::boolean) RETURNING id INTO result;
 ELSE
  SELECT * INTO old FROM app.customers WHERE id=result FOR UPDATE;
  IF NOT FOUND OR old.version::text<>d->>'version' THEN RAISE EXCEPTION 'pos: Customer changed. Reload before saving.' USING ERRCODE='23514'; END IF;
  UPDATE app.customers SET code=d->>'code',name=d->>'name',business_name=d->>'business_name',phone=d->>'phone',address=d->>'address',customer_type=d->>'customer_type',credit_limit_mmk=(d->>'credit_limit_mmk')::numeric,notes=d->>'notes',is_active=(d->>'is_active')::boolean,version=version+1 WHERE id=result;
 END IF;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value) VALUES(actor,'customers.save','customers',result,to_jsonb(old),d);
 RETURN result;
END $$;
CREATE FUNCTION app.customer_price(d jsonb, actor uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c app.customers; old jsonb;
BEGIN
 SELECT * INTO c FROM app.customers WHERE id=(d->>'customer_id')::uuid FOR UPDATE;
 IF NOT FOUND OR c.version::text<>d->>'version' THEN RAISE EXCEPTION 'pos: Customer changed. Reload before saving.' USING ERRCODE='23514'; END IF;
 SELECT to_jsonb(p) INTO old FROM app.customer_prices p WHERE customer_id=c.id AND product_id=(d->>'product_id')::uuid AND unit_code=d->>'unit_code';
 IF (d->>'remove')::boolean THEN
  DELETE FROM app.customer_prices WHERE customer_id=c.id AND product_id=(d->>'product_id')::uuid AND unit_code=d->>'unit_code';
 ELSE
  INSERT INTO app.customer_prices(customer_id,product_id,unit_code,price_mmk) VALUES(c.id,(d->>'product_id')::uuid,d->>'unit_code',(d->>'price_mmk')::numeric)
  ON CONFLICT(customer_id,product_id,unit_code) DO UPDATE SET price_mmk=excluded.price_mmk;
 END IF;
 UPDATE app.customers SET version=version+1 WHERE id=c.id;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value) VALUES(actor,'customers.price','customers',c.id,old,d);
END $$;
CREATE FUNCTION app.customer_payment(d jsonb, actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE prior app.payments; s app.sales; payment uuid; balance numeric; amount numeric=(d->>'amount_mmk')::numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO prior FROM app.payments WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
  IF prior.recorded_by<>actor OR prior.request_payload<>d THEN RAISE EXCEPTION 'pos: Payment request already used.' USING ERRCODE='23514'; END IF;
  RETURN prior.id;
 END IF;
 PERFORM id FROM app.customers WHERE id=(d->>'customer_id')::uuid FOR UPDATE;
 SELECT * INTO s FROM app.sales WHERE id=(d->>'sale_id')::uuid AND customer_id=(d->>'customer_id')::uuid AND status='POSTED' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'pos: Choose a posted invoice for this customer.' USING ERRCODE='23514'; END IF;
 SELECT outstanding_mmk INTO balance FROM app.customer_debts WHERE sale_id=s.id;
 IF amount<=0 OR amount>balance THEN RAISE EXCEPTION 'pos: Payment must be positive and cannot exceed the outstanding balance.' USING ERRCODE='23514'; END IF;
 INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,customer_id,paid_at,reference_number,recorded_by,request_id,request_payload)
 VALUES('COL-'||(d->>'request_id'),'IN',d->>'method','MMK',amount,1,s.customer_id,now(),d->>'reference',actor,(d->>'request_id')::uuid,d) RETURNING id INTO payment;
 INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) VALUES(payment,s.id,amount,amount,amount);
 UPDATE app.payments SET status='POSTED',posted_at=now() WHERE id=payment;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'customers.payment','payments',payment,d);
 RETURN payment;
END $$;
CREATE OR REPLACE VIEW app.customer_debts AS
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
SELECT *, CASE WHEN outstanding_mmk<=0 THEN 'PAID' WHEN due_date<app.business_date() THEN 'OVERDUE' WHEN amount_paid_mmk>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END AS payment_status FROM balances;


CREATE OR REPLACE FUNCTION app.pos_sale(d jsonb, actor uuid, discounts boolean, below_cost boolean, preview boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE old app.sales; customer app.customers; product app.products; pack app.product_units; x jsonb; alloc jsonb; lines jsonb='[]'; allocations jsonb; stock record;
 warehouse uuid=(d->>'warehouse_id')::uuid; customer_id uuid=nullif(d->>'customer_id','')::uuid;
 qty numeric; needed numeric; take numeric; price numeric; discount numeric; line_total numeric; line_cost numeric; total numeric=0; costs numeric=0;
 tender numeric=(d->>'tender_mmk')::numeric; paid numeric; change numeric; debt numeric; outstanding numeric;
 doc jsonb; quote text; sale uuid; sale_item uuid; sale_batch uuid; payment uuid; invoice text; line_no int=0; needs_approval boolean=false; approval uuid;
BEGIN
 IF NOT preview THEN
  PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
  SELECT * INTO old FROM app.sales WHERE request_id=(d->>'request_id')::uuid;
  IF FOUND THEN IF old.created_by<>actor OR old.request_payload<>d THEN RAISE EXCEPTION 'pos: This checkout request was already used with different contents.' USING ERRCODE='23514'; END IF; RETURN jsonb_build_object('id',old.id,'invoice_number',old.invoice_number); END IF;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM app.warehouses WHERE id=warehouse AND is_active) THEN RAISE EXCEPTION 'pos: Choose an active warehouse.' USING ERRCODE='23514'; END IF;
 IF customer_id IS NOT NULL THEN
  SELECT * INTO customer FROM app.customers WHERE id=customer_id AND is_active FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'pos: Customer is no longer active.' USING ERRCODE='23514'; END IF;
 END IF;
 IF jsonb_array_length(d->'items')=0 OR jsonb_array_length(d->'items')>100 OR (SELECT count(DISTINCT value->>'product_id') FROM jsonb_array_elements(d->'items'))<>jsonb_array_length(d->'items') THEN RAISE EXCEPTION 'pos: Use one cart line per product; choose its selling unit on that line.' USING ERRCODE='23514'; END IF;
 -- A stable lock order prevents concurrent terminals overselling and prices changing during checkout.
 PERFORM p.id FROM app.products p WHERE p.id IN(SELECT (value->>'product_id')::uuid FROM jsonb_array_elements(d->'items')) ORDER BY p.id FOR UPDATE;
 PERFORM i.batch_id FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id WHERE i.warehouse_id=warehouse AND b.product_id IN(SELECT (value->>'product_id')::uuid FROM jsonb_array_elements(d->'items')) ORDER BY i.batch_id FOR UPDATE OF i;
 FOR x IN SELECT value FROM jsonb_array_elements(d->'items') LOOP
  SELECT * INTO product FROM app.products WHERE id=(x->>'product_id')::uuid AND is_active AND archived_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'pos: A product is inactive or unavailable.' USING ERRCODE='23514'; END IF;
  SELECT * INTO pack FROM app.product_units WHERE product_id=product.id AND unit_code=x->>'unit_code' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'pos: Selling unit changed. Reload the product.' USING ERRCODE='23514'; END IF;
  price=CASE d->>'pricing_mode' WHEN 'RETAIL' THEN pack.retail_price_mmk WHEN 'WHOLESALE' THEN pack.wholesale_price_mmk END;
  price=coalesce((SELECT cp.price_mmk FROM app.customer_prices cp WHERE cp.customer_id=customer.id AND cp.product_id=product.id AND cp.unit_code=pack.unit_code),price);
  IF price IS NULL OR price<>(x->>'unit_price_mmk')::numeric OR pack.units_per_pack<>(x->>'units_per_pack')::numeric THEN RAISE EXCEPTION 'pos: Price or packaging changed. Refresh the cart before checkout.' USING ERRCODE='23514'; END IF;
  qty=(x->>'quantity')::numeric; needed=qty*pack.units_per_pack; discount=(x->>'discount_mmk')::numeric;
  IF qty<=0 OR needed<>round(needed,6) OR discount<0 OR discount>qty*price THEN RAISE EXCEPTION 'pos: Invalid quantity or discount.' USING ERRCODE='23514'; END IF;
  IF discount>0 AND (NOT discounts OR btrim(d->>'reason')='') THEN RAISE EXCEPTION 'pos: Discounts require permission and a reason.' USING ERRCODE='23514'; END IF;
  allocations='[]';line_cost=0;
  FOR stock IN SELECT * FROM app.pos_eligible_stock WHERE warehouse_id=warehouse AND product_id=product.id ORDER BY received_at,batch_id LOOP
   take=least(needed,stock.available_quantity);
   allocations=allocations||jsonb_build_array(jsonb_build_object('batch_id',stock.batch_id,'quantity',take::text,'unit_cost_mmk',stock.actual_unit_cost_mmk::text,'total_cost_mmk',round(take*stock.actual_unit_cost_mmk,4)::text));
   line_cost=line_cost+round(take*stock.actual_unit_cost_mmk,4);needed=needed-take;
   EXIT WHEN needed=0;
  END LOOP;
  IF needed>0 THEN RAISE EXCEPTION 'pos: Not enough unreserved, non-expired, costed stock. Refresh availability.' USING ERRCODE='23514'; END IF;
  line_total=round(qty*price-discount,4);
  needs_approval=needs_approval OR line_total<line_cost;
  total=total+line_total; costs=costs+line_cost;
  lines=lines||jsonb_build_array(jsonb_build_object('product_id',product.id,'product_name',product.name,'sku',product.sku,'unit_code',pack.unit_code,'units_per_pack',pack.units_per_pack::text,'quantity',qty::text,'base_quantity',(qty*pack.units_per_pack)::text,'unit_price_mmk',price::text,'discount_mmk',discount::text,'total_mmk',line_total::text,'cost_mmk',line_cost::text,'allocations',allocations,'below_cost',line_total<line_cost));
 END LOOP;
 IF tender<0 OR (d->>'payment_method'<>'CASH' AND tender>total) THEN RAISE EXCEPTION 'pos: Non-cash payment cannot exceed the invoice total.' USING ERRCODE='23514'; END IF;
 paid=least(tender,total);change=tender-paid;debt=total-paid;
 IF debt>0 THEN
  IF customer_id IS NULL OR nullif(d->>'due_date','') IS NULL OR (d->>'due_date')::date<app.business_date() THEN RAISE EXCEPTION 'pos: Credit sales require a customer and a valid due date.' USING ERRCODE='23514'; END IF;
  SELECT coalesce(sum(greatest(outstanding_mmk,0)),0) INTO outstanding FROM app.customer_debts WHERE customer_debts.customer_id=customer.id;
  IF outstanding+debt>customer.credit_limit_mmk THEN RAISE EXCEPTION 'pos: This sale exceeds the customer credit limit.' USING ERRCODE='23514'; END IF;
 END IF;
 doc=jsonb_build_object('business_date',app.business_date(),'warehouse_id',warehouse,'warehouse_name',(SELECT name FROM app.warehouses WHERE id=warehouse),'customer_id',customer_id,'customer_name',coalesce(customer.name,'Walk-in customer'),'pricing_mode',d->>'pricing_mode','lines',lines,'total_mmk',total::text,'cost_mmk',costs::text,'profit_mmk',(total-costs)::text,'tender_mmk',tender::text,'paid_mmk',paid::text,'change_mmk',change::text,'outstanding_mmk',debt::text,'payment_method',d->>'payment_method','payment_reference',d->>'payment_reference','due_date',nullif(d->>'due_date',''),'reason',d->>'reason');
 quote=md5(doc::text);
 IF preview THEN RETURN doc||jsonb_build_object('quote_hash',quote,'requires_below_cost_approval',needs_approval,'can_approve_below_cost',below_cost); END IF;
 IF needs_approval AND (NOT below_cost OR NOT coalesce((d->>'approve_below_cost')::boolean,false) OR coalesce(btrim(d->>'reason'),'')='') THEN
  RAISE EXCEPTION 'pos: Below-cost sales require authorized approval, explicit confirmation and a reason.' USING ERRCODE='23514';
 END IF;
 IF quote IS DISTINCT FROM d->>'quote_hash' THEN RAISE EXCEPTION 'pos: Checkout details changed. Review the updated quote before posting.' USING ERRCODE='23514'; END IF;
 invoice='PT-'||to_char(app.business_date(),'YYYYMMDD')||'-'||lpad(nextval('app.invoice_sequence')::text,8,'0');
 INSERT INTO app.sales(invoice_number,customer_id,warehouse_id,pricing_mode,sold_at,due_date,created_by,notes,request_id,request_payload,invoice_document)
 VALUES(invoice,customer_id,warehouse,d->>'pricing_mode',now(),CASE WHEN debt>0 THEN (d->>'due_date')::date END,actor,nullif(d->>'reason',''),(d->>'request_id')::uuid,d,doc) RETURNING id INTO sale;
 FOR x IN SELECT value FROM jsonb_array_elements(lines) LOOP
  line_no=line_no+1;
  INSERT INTO app.sale_items(sale_id,line_number,product_id,unit_code,units_per_pack,quantity,unit_price_mmk,discount_mmk,price_reason)
  VALUES(sale,line_no,(x->>'product_id')::uuid,x->>'unit_code',(x->>'units_per_pack')::numeric,(x->>'quantity')::numeric,(x->>'unit_price_mmk')::numeric,(x->>'discount_mmk')::numeric,nullif(d->>'reason','')) RETURNING id INTO sale_item;
  FOR alloc IN SELECT value FROM jsonb_array_elements(x->'allocations') LOOP
   INSERT INTO app.sale_item_batches(sale_item_id,batch_id,product_id,quantity,unit_cost_mmk) VALUES(sale_item,(alloc->>'batch_id')::uuid,(x->>'product_id')::uuid,(alloc->>'quantity')::numeric,(alloc->>'unit_cost_mmk')::numeric) RETURNING id INTO sale_batch;
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,unit_cost_mmk,sale_item_batch_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(warehouse,(alloc->>'batch_id')::uuid,'SALE',-(alloc->>'quantity')::numeric,(alloc->>'unit_cost_mmk')::numeric,sale_batch,'sale:'||sale_batch,now(),actor,invoice);
  END LOOP;
 END LOOP;
 IF paid>0 THEN
  INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,customer_id,paid_at,reference_number,recorded_by) VALUES('PAY-'||invoice,'IN',d->>'payment_method','MMK',paid,1,customer_id,now(),nullif(d->>'payment_reference',''),actor) RETURNING id INTO payment;
  INSERT INTO app.payment_allocations(payment_id,sale_id,settlement_mmk,applied_mmk,applied_original) VALUES(payment,sale,paid,paid,paid);
  UPDATE app.payments SET status='POSTED',posted_at=now() WHERE id=payment;
 END IF;
 IF needs_approval THEN
  INSERT INTO app.approvals(permission_code,sale_id,requested_by,reason,request_payload,request_hash,status,decided_by,decided_at,decision_note,consumed_at)
  VALUES('sales.sell_below_cost',sale,actor,d->>'reason',doc,sha256(convert_to(doc::text,'UTF8')),'APPROVED',actor,now(),d->>'reason',now()) RETURNING id INTO approval;
  INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value,reason)
  VALUES(actor,'sales.below_cost.approved','sales',sale,jsonb_build_object('approval_id',approval,'request_id',d->>'request_id','quote_hash',quote,'approved_sale',doc),d->>'reason');
 END IF;
 UPDATE app.sales SET status='POSTED',posted_at=now() WHERE id=sale;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value,reason) VALUES(actor,'sales.post','sales',sale,doc,nullif(d->>'reason',''));
 RETURN jsonb_build_object('id',sale,'invoice_number',invoice);
END $$;
