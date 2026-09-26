-- Phase 15: approval is consumed in the same transaction as the exact FIFO sale.
CREATE UNIQUE INDEX sale_below_cost_approval ON app.approvals(sale_id)
 WHERE permission_code='sales.sell_below_cost' AND consumed_at IS NOT NULL;
CREATE TRIGGER consumed_sale_approval_immutable BEFORE UPDATE OR DELETE ON app.approvals
 FOR EACH ROW WHEN (OLD.permission_code='sales.sell_below_cost' AND OLD.consumed_at IS NOT NULL)
 EXECUTE FUNCTION app.deny_mutation();

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
