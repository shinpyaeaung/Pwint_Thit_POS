CREATE TABLE app.stock_operations (
 request_id uuid PRIMARY KEY, kind text NOT NULL, actor_id uuid NOT NULL REFERENCES app.users(id),
 payload jsonb NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX stock_operations_actor ON app.stock_operations(actor_id);
CREATE TRIGGER stock_operations_immutable BEFORE UPDATE OR DELETE ON app.stock_operations FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE TRIGGER damage_immutable BEFORE UPDATE OR DELETE ON app.damaged_products FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE TRIGGER missing_immutable BEFORE UPDATE OR DELETE ON app.missing_products FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
ALTER TABLE app.damaged_products ADD COLUMN sale_id uuid REFERENCES app.sales(id);
ALTER TABLE app.damaged_products ADD COLUMN actual_unit_cost_mmk numeric(24,8) CHECK(actual_unit_cost_mmk>=0 AND actual_unit_cost_mmk<>'NaN');
ALTER TABLE app.damaged_products ADD COLUMN discount_loss_mmk numeric(20,4) CHECK(discount_loss_mmk>=0 AND discount_loss_mmk<>'NaN');
CREATE INDEX damaged_sale ON app.damaged_products(sale_id);
ALTER TABLE app.sales_return_items ADD COLUMN unit_cost_mmk numeric(24,8) CHECK(unit_cost_mmk>=0 AND unit_cost_mmk<>'NaN');
CREATE UNIQUE INDEX exchange_replacement_unique ON app.sales_returns(replacement_sale_id) WHERE replacement_sale_id IS NOT NULL AND status='POSTED';
CREATE TRIGGER consumed_refund_approval_immutable BEFORE UPDATE OR DELETE ON app.approvals
 FOR EACH ROW WHEN (OLD.permission_code='refunds.approve' AND OLD.consumed_at IS NOT NULL) EXECUTE FUNCTION app.deny_mutation();

CREATE FUNCTION app.stock_operation_prior(d jsonb, actor uuid, operation text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE old app.stock_operations;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.stock_operations WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN
  IF old.kind<>operation OR old.actor_id<>actor OR old.payload<>d THEN RAISE EXCEPTION 'pos: Request already used with different details.' USING ERRCODE='23514'; END IF;
  RETURN old.result;
 END IF;
 RETURN NULL;
END $$;
CREATE FUNCTION app.stock_operation_finish(d jsonb, actor uuid, operation text, result jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO app.stock_operations(request_id,kind,actor_id,payload,result) VALUES((d->>'request_id')::uuid,operation,actor,d,result);
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value,reason) VALUES(actor,operation,'stock_operations',(d->>'request_id')::uuid,jsonb_build_object('request',d,'result',result),d->>'reason');
 RETURN result;
END $$;
CREATE FUNCTION app.stock_issue(d jsonb, actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE prior jsonb; b app.batches; i app.inventory; record_id uuid; qty numeric=(d->>'quantity')::numeric; bucket text=d->>'bucket'; kind text=d->>'kind'; sell_delta numeric=0; damage_delta numeric=0;
BEGIN
 prior=app.stock_operation_prior(d,actor,'stock.issue'); IF prior IS NOT NULL THEN RETURN prior; END IF;
 SELECT * INTO b FROM app.batches WHERE id=(d->>'batch_id')::uuid;
 IF NOT FOUND OR b.finalized_at IS NULL OR b.actual_unit_cost_mmk IS NULL THEN RAISE EXCEPTION 'pos: Choose a finalized batch with actual cost.' USING ERRCODE='23514'; END IF;
 PERFORM id FROM app.products WHERE id=b.product_id FOR UPDATE;
 SELECT * INTO i FROM app.inventory WHERE batch_id=b.id AND warehouse_id=(d->>'warehouse_id')::uuid FOR UPDATE;
 IF NOT FOUND OR i.version::text<>d->>'version' OR qty<=0 OR (bucket='SELLABLE' AND qty>i.available_quantity) OR (bucket='DAMAGED' AND qty>i.damaged_quantity) THEN RAISE EXCEPTION 'pos: Stock changed or quantity is unavailable. Refresh stock.' USING ERRCODE='23514'; END IF;
 IF kind='DAMAGE' THEN
  sell_delta=-qty;damage_delta=qty;
 ELSIF kind='DISCARD' THEN damage_delta=-qty;
 ELSIF kind='MISSING' THEN
  IF bucket='SELLABLE' THEN sell_delta=-qty; ELSE damage_delta=-qty; END IF;
 ELSE RAISE EXCEPTION 'pos: Invalid stock operation.' USING ERRCODE='23514'; END IF;
 IF (kind='DAMAGE' AND bucket<>'SELLABLE') OR (kind='DISCARD' AND bucket<>'DAMAGED') THEN RAISE EXCEPTION 'pos: Choose the correct stock bucket.' USING ERRCODE='23514'; END IF;
 IF kind='MISSING' THEN
  INSERT INTO app.missing_products(product_id,batch_id,warehouse_id,quantity,estimated_loss_mmk,reason,occurred_at,recorded_by,notes) VALUES(b.product_id,b.id,i.warehouse_id,qty,round(qty*b.actual_unit_cost_mmk,4),d->>'reason',now(),actor,d->>'notes') RETURNING id INTO record_id;
  INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,missing_product_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(i.warehouse_id,b.id,'MISSING',sell_delta,damage_delta,b.actual_unit_cost_mmk,record_id,'missing:'||record_id,now(),actor,d->>'reason');
 ELSE
  INSERT INTO app.damaged_products(product_id,batch_id,warehouse_id,quantity,estimated_loss_mmk,reason,occurred_at,recorded_by,disposition,notes,actual_unit_cost_mmk) VALUES(b.product_id,b.id,i.warehouse_id,qty,round(qty*b.actual_unit_cost_mmk,4),d->>'reason',now(),actor,CASE WHEN kind='DAMAGE' THEN 'QUARANTINE' ELSE 'DISCARD' END,d->>'notes',b.actual_unit_cost_mmk) RETURNING id INTO record_id;
  INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,damaged_product_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(i.warehouse_id,b.id,'DAMAGE',sell_delta,damage_delta,b.actual_unit_cost_mmk,record_id,'damage:'||record_id,now(),actor,d->>'reason');
 END IF;
 RETURN app.stock_operation_finish(d,actor,'stock.issue',jsonb_build_object('id',record_id));
END $$;
CREATE FUNCTION app.sale_balance(sale uuid) RETURNS numeric LANGUAGE sql STABLE AS $$
 SELECT t.total_mmk
 -coalesce((SELECT sum(a.applied_mmk) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.sale_id=sale AND p.status='POSTED' AND p.direction='IN'),0)
 -coalesce((SELECT sum(i.refund_mmk) FROM app.sales_return_items i JOIN app.sales_returns r ON r.id=i.sales_return_id WHERE r.sale_id=sale AND r.status='POSTED'),0)
 +coalesce((SELECT sum(a.applied_mmk) FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id JOIN app.sales_returns r ON r.id=a.sales_return_id WHERE r.sale_id=sale AND r.status='POSTED' AND p.status='POSTED' AND p.direction='OUT'),0)
 FROM app.sale_totals t WHERE t.sale_id=sale
$$;
CREATE FUNCTION app.sales_return_post(d jsonb, actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE prior jsonb; s app.sales; si app.sale_items; sb app.sale_item_batches; x jsonb; result uuid; item uuid; payment uuid; approval uuid; qty numeric; returned numeric; line_returned numeric; prior_credit numeric; credit numeric; total numeric=0; balance numeric; refund numeric; disposition text; replacement uuid=nullif(d->>'replacement_sale_id','')::uuid; kind text=d->>'resolution';
BEGIN
 prior=app.stock_operation_prior(d,actor,'returns.sale'); IF prior IS NOT NULL THEN RETURN prior; END IF;
 SELECT * INTO s FROM app.sales WHERE id=(d->>'sale_id')::uuid AND status='POSTED';
 IF NOT FOUND THEN RAISE EXCEPTION 'pos: Choose a posted sale.' USING ERRCODE='23514'; END IF;
 PERFORM id FROM app.customers WHERE id=s.customer_id FOR UPDATE;
 PERFORM id FROM app.sales WHERE id IN(s.id,replacement) ORDER BY id FOR UPDATE;
 IF kind='CREDIT' AND s.customer_id IS NULL THEN RAISE EXCEPTION 'pos: Walk-in returns require a refund.' USING ERRCODE='23514'; END IF;
 IF kind='EXCHANGE' THEN
  IF replacement IS NULL OR replacement=s.id OR NOT EXISTS(SELECT 1 FROM app.sales WHERE id=replacement AND status='POSTED' AND customer_id IS NOT DISTINCT FROM s.customer_id) OR EXISTS(SELECT 1 FROM app.sales_returns WHERE replacement_sale_id=replacement AND status='POSTED') THEN RAISE EXCEPTION 'pos: Choose an unused posted replacement invoice for the same customer.' USING ERRCODE='23514'; END IF;
 ELSIF replacement IS NOT NULL THEN RAISE EXCEPTION 'pos: Replacement invoice is only valid for an exchange.' USING ERRCODE='23514'; END IF;
 PERFORM p.id FROM app.products p WHERE p.id IN(SELECT product_id FROM app.sale_items WHERE sale_id=s.id) ORDER BY p.id FOR UPDATE;
 PERFORM i.batch_id FROM app.inventory i WHERE i.warehouse_id=s.warehouse_id AND i.batch_id IN(SELECT b.batch_id FROM app.sale_item_batches b JOIN app.sale_items j ON j.id=b.sale_item_id WHERE j.sale_id=s.id) ORDER BY i.batch_id FOR UPDATE;
 balance=app.sale_balance(s.id);
 INSERT INTO app.sales_returns(return_number,sale_id,return_type,replacement_sale_id,returned_at,reason,created_by) VALUES('SR-'||(d->>'request_id'),s.id,kind,replacement,now(),d->>'reason',actor) RETURNING id INTO result;
 FOR x IN SELECT value FROM jsonb_array_elements(d->'items') LOOP
  qty=(x->>'quantity')::numeric;disposition=x->>'disposition';
  SELECT b.* INTO sb FROM app.sale_item_batches b JOIN app.sale_items j ON j.id=b.sale_item_id WHERE b.id=(x->>'sale_item_batch_id')::uuid AND j.sale_id=s.id;
  IF NOT FOUND THEN RAISE EXCEPTION 'pos: Return item does not belong to this invoice.' USING ERRCODE='23514'; END IF;
  SELECT * INTO si FROM app.sale_items WHERE id=sb.sale_item_id;
  IF disposition='SELLABLE' AND EXISTS(SELECT 1 FROM jsonb_array_elements(s.invoice_document->'lines') line WHERE line->>'product_id'=si.product_id::text AND line->>'stock_bucket'='DAMAGED') THEN RAISE EXCEPTION 'pos: Goods sold as damaged must return as damaged or discard.' USING ERRCODE='23514'; END IF;
  SELECT coalesce(sum(i.quantity),0) INTO returned FROM app.sales_return_items i JOIN app.sales_returns r ON r.id=i.sales_return_id WHERE i.sale_item_batch_id=sb.id AND (r.status='POSTED' OR r.id=result);
  SELECT coalesce(sum(i.quantity),0),coalesce(sum(i.refund_mmk),0) INTO line_returned,prior_credit FROM app.sales_return_items i JOIN app.sales_returns r ON r.id=i.sales_return_id WHERE i.sale_item_id=si.id AND (r.status='POSTED' OR r.id=result);
  IF qty<=0 OR qty>sb.quantity-returned THEN RAISE EXCEPTION 'pos: Return quantity exceeds the remaining sold quantity.' USING ERRCODE='23514'; END IF;
  IF disposition='SELLABLE' AND EXISTS(SELECT 1 FROM app.batches b JOIN app.products p ON p.id=b.product_id WHERE b.id=sb.batch_id AND (b.expires_on<app.business_date() OR (p.tracks_expiry AND b.expires_on IS NULL))) THEN RAISE EXCEPTION 'pos: Expired or undated expiry-tracked goods must return as damaged or discard.' USING ERRCODE='23514'; END IF;
  credit=CASE WHEN qty=si.base_quantity-line_returned THEN si.total_mmk-prior_credit ELSE least(si.total_mmk-prior_credit,round(si.total_mmk*qty/si.base_quantity,4)) END;total=total+credit;
  INSERT INTO app.sales_return_items(sales_return_id,sale_id,sale_item_id,sale_item_batch_id,product_id,quantity,refund_mmk,disposition,unit_cost_mmk) VALUES(result,s.id,si.id,sb.id,sb.product_id,qty,credit,disposition,sb.unit_cost_mmk) RETURNING id INTO item;
  INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,sales_return_item_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(s.warehouse_id,sb.batch_id,'SALE_RETURN',CASE WHEN disposition='SELLABLE' THEN qty ELSE 0 END,CASE WHEN disposition<>'SELLABLE' THEN qty ELSE 0 END,sb.unit_cost_mmk,item,'return:'||item,now(),actor,d->>'reason');
  IF disposition='DISCARD' THEN
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,damaged_delta,unit_cost_mmk,sales_return_item_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(s.warehouse_id,sb.batch_id,'SALE_RETURN',-qty,sb.unit_cost_mmk,item,'return-discard:'||item,now(),actor,d->>'reason');
  END IF;
 END LOOP;
 refund=CASE WHEN kind='CREDIT' THEN 0 ELSE greatest(total-greatest(balance,0),0) END;
 IF refund>0 THEN
  INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,customer_id,paid_at,reference_number,recorded_by) VALUES('REF-'||result,'OUT',d->>'method','MMK',refund,1,s.customer_id,now(),d->>'reference',actor) RETURNING id INTO payment;
  INSERT INTO app.payment_allocations(payment_id,sales_return_id,settlement_mmk,applied_mmk,applied_original) VALUES(payment,result,refund,refund,refund);
  UPDATE app.payments SET status='POSTED',posted_at=now() WHERE id=payment;
 END IF;
 IF kind<>'CREDIT' THEN
  INSERT INTO app.approvals(permission_code,sales_return_id,requested_by,reason,request_payload,request_hash,status,decided_by,decided_at,decision_note,consumed_at) VALUES('refunds.approve',result,actor,d->>'reason',d,sha256(convert_to(d::text,'UTF8')),'APPROVED',actor,now(),d->>'reason',now()) RETURNING id INTO approval;
  INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value,reason) VALUES(actor,'refunds.approved','sales_returns',result,jsonb_build_object('approval_id',approval,'credit_mmk',total::text,'refund_mmk',refund::text),d->>'reason');
 END IF;
 UPDATE app.sales_returns SET status='POSTED',posted_at=now() WHERE id=result;
 RETURN app.stock_operation_finish(d,actor,'returns.sale',jsonb_build_object('id',result,'credit_mmk',total::text,'refund_mmk',refund::text));
END $$;
CREATE FUNCTION app.purchase_return_post(d jsonb, actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE prior jsonb; p app.purchases; pi app.purchase_items; b app.batches; i app.inventory; x jsonb; result uuid; item uuid; payment uuid; qty numeric; returned numeric; credited numeric; credit numeric; total numeric=0; balance numeric; refund numeric; bucket text;
BEGIN
 prior=app.stock_operation_prior(d,actor,'returns.purchase');IF prior IS NOT NULL THEN RETURN prior; END IF;
 SELECT * INTO p FROM app.purchases WHERE id=(d->>'purchase_id')::uuid AND status='POSTED' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'pos: Choose a posted supplier purchase.' USING ERRCODE='23514'; END IF;
 PERFORM pr.id FROM app.products pr WHERE pr.id IN(SELECT product_id FROM app.purchase_items WHERE purchase_id=p.id) ORDER BY pr.id FOR UPDATE;
 PERFORM inv.batch_id FROM app.inventory inv WHERE inv.warehouse_id=(d->>'warehouse_id')::uuid AND inv.batch_id IN(SELECT (value->>'batch_id')::uuid FROM jsonb_array_elements(d->'items')) ORDER BY inv.batch_id FOR UPDATE;
 SELECT outstanding_original INTO balance FROM app.supplier_payables WHERE purchase_id=p.id;
 INSERT INTO app.purchase_returns(return_number,purchase_id,returned_at,resolution,reason,created_by) VALUES('PR-'||(d->>'request_id'),p.id,now(),d->>'resolution',d->>'reason',actor) RETURNING id INTO result;
 FOR x IN SELECT value FROM jsonb_array_elements(d->'items') LOOP
  qty=(x->>'quantity')::numeric;bucket=x->>'bucket';
  SELECT pb.* INTO b FROM app.batches pb JOIN app.goods_receiving_items gr ON gr.id=pb.receiving_item_id JOIN app.shipment_items sh ON sh.id=gr.shipment_item_id JOIN app.purchase_items j ON j.id=sh.purchase_item_id WHERE pb.id=(x->>'batch_id')::uuid AND j.purchase_id=p.id;
  IF NOT FOUND OR b.actual_unit_cost_mmk IS NULL THEN RAISE EXCEPTION 'pos: Batch does not belong to this purchase or has no actual cost.' USING ERRCODE='23514'; END IF;
  SELECT j.* INTO pi FROM app.purchase_items j JOIN app.shipment_items sh ON sh.purchase_item_id=j.id JOIN app.goods_receiving_items gr ON gr.shipment_item_id=sh.id WHERE gr.id=b.receiving_item_id;
  SELECT * INTO i FROM app.inventory WHERE batch_id=b.id AND warehouse_id=(d->>'warehouse_id')::uuid;
  IF NOT FOUND OR qty<=0 OR (bucket='SELLABLE' AND qty>i.available_quantity) OR (bucket='DAMAGED' AND qty>i.damaged_quantity) THEN RAISE EXCEPTION 'pos: Return quantity exceeds available stock.' USING ERRCODE='23514'; END IF;
  SELECT coalesce(sum(j.quantity),0),coalesce(sum(j.credit_original),0) INTO returned,credited FROM app.purchase_return_items j JOIN app.purchase_returns r ON r.id=j.purchase_return_id WHERE j.purchase_item_id=pi.id AND (r.status='POSTED' OR r.id=result);
  IF qty>pi.base_quantity-returned THEN RAISE EXCEPTION 'pos: Quantity exceeds the original purchase remaining for return.' USING ERRCODE='23514'; END IF;
  credit=CASE WHEN qty=pi.base_quantity-returned THEN pi.total_original-credited ELSE least(pi.total_original-credited,round(pi.total_original*qty/pi.base_quantity,4)) END;total=total+credit;
  INSERT INTO app.purchase_return_items(purchase_return_id,purchase_id,purchase_item_id,product_id,batch_id,quantity,credit_original,credit_mmk,inventory_cost_mmk) VALUES(result,p.id,pi.id,pi.product_id,b.id,qty,credit,round(credit*p.mmk_per_unit,4),round(qty*b.actual_unit_cost_mmk,4)) RETURNING id INTO item;
  INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,purchase_return_item_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(i.warehouse_id,b.id,'PURCHASE_RETURN',CASE WHEN bucket='SELLABLE' THEN -qty ELSE 0 END,CASE WHEN bucket='DAMAGED' THEN -qty ELSE 0 END,b.actual_unit_cost_mmk,item,'purchase-return:'||item,now(),actor,d->>'reason');
 END LOOP;
 refund=CASE WHEN d->>'resolution'='REFUND' THEN greatest(total-greatest(balance,0),0) ELSE 0 END;
 IF refund>0 THEN
  INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,supplier_id,paid_at,reference_number,recorded_by) VALUES('SREF-'||result,'IN',d->>'method',p.currency_code,refund,p.mmk_per_unit,p.supplier_id,now(),d->>'reference',actor) RETURNING id INTO payment;
  INSERT INTO app.payment_allocations(payment_id,purchase_return_id,settlement_mmk,applied_mmk,applied_original) VALUES(payment,result,round(refund*p.mmk_per_unit,4),round(refund*p.mmk_per_unit,4),refund);
  UPDATE app.payments SET status='POSTED',posted_at=now() WHERE id=payment;
 END IF;
 IF d->>'resolution'='REFUND' THEN
  INSERT INTO app.approvals(permission_code,purchase_return_id,requested_by,reason,request_payload,request_hash,status,decided_by,decided_at,decision_note,consumed_at) VALUES('refunds.approve',result,actor,d->>'reason',d,sha256(convert_to(d::text,'UTF8')),'APPROVED',actor,now(),d->>'reason',now());
  INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value,reason) VALUES(actor,'refunds.approved','purchase_returns',result,jsonb_build_object('currency_code',p.currency_code,'credit_original',total::text,'refund_original',refund::text),d->>'reason');
 END IF;
 UPDATE app.purchase_returns SET status='POSTED',posted_at=now() WHERE id=result;
 RETURN app.stock_operation_finish(d,actor,'returns.purchase',jsonb_build_object('id',result,'currency_code',p.currency_code,'credit_original',total::text,'refund_original',refund::text));
END $$;

CREATE VIEW app.pos_damaged_stock AS
 SELECT i.warehouse_id,i.batch_id,i.damaged_quantity AS available_quantity,b.product_id,b.received_at,b.actual_unit_cost_mmk
 FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id
 WHERE i.damaged_quantity>0 AND b.finalized_at IS NOT NULL AND b.actual_unit_cost_mmk IS NOT NULL
 AND (b.expires_on IS NULL OR b.expires_on>=app.business_date()) AND (NOT p.tracks_expiry OR b.expires_on IS NOT NULL);

CREATE OR REPLACE FUNCTION app.pos_sale(d jsonb, actor uuid, discounts boolean, below_cost boolean, preview boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE old app.sales; customer app.customers; product app.products; pack app.product_units; x jsonb; alloc jsonb; lines jsonb='[]'; allocations jsonb; stock record;
 warehouse uuid=(d->>'warehouse_id')::uuid; customer_id uuid=nullif(d->>'customer_id','')::uuid;
 qty numeric; needed numeric; take numeric; price numeric; discount numeric; line_total numeric; line_cost numeric; total numeric=0; costs numeric=0;
 tender numeric=(d->>'tender_mmk')::numeric; paid numeric; change numeric; debt numeric; outstanding numeric;
 doc jsonb; quote text; sale uuid; sale_item uuid; sale_batch uuid; payment uuid; invoice text; line_no int=0; needs_approval boolean=false; approval uuid; original_price numeric; damage_record uuid;
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
  original_price=price;
  IF x->>'stock_bucket'='DAMAGED' THEN
   IF price IS NULL OR (x->>'unit_price_mmk')::numeric>price OR pack.units_per_pack<>1 OR nullif(x->>'batch_id','') IS NULL OR coalesce(btrim(d->>'reason'),'')='' THEN RAISE EXCEPTION 'pos: Reduced damaged sales require a base unit, a configured original price, a reduced price and a reason.' USING ERRCODE='23514'; END IF;
   price=(x->>'unit_price_mmk')::numeric;
  END IF;
  IF price IS NULL OR price<>(x->>'unit_price_mmk')::numeric OR pack.units_per_pack<>(x->>'units_per_pack')::numeric THEN RAISE EXCEPTION 'pos: Price or packaging changed. Refresh the cart before checkout.' USING ERRCODE='23514'; END IF;
  qty=(x->>'quantity')::numeric; needed=qty*pack.units_per_pack; discount=(x->>'discount_mmk')::numeric;
  IF qty<=0 OR needed<>round(needed,6) OR discount<0 OR discount>qty*price THEN RAISE EXCEPTION 'pos: Invalid quantity or discount.' USING ERRCODE='23514'; END IF;
  IF discount>0 AND (NOT discounts OR btrim(d->>'reason')='') THEN RAISE EXCEPTION 'pos: Discounts require permission and a reason.' USING ERRCODE='23514'; END IF;
  allocations='[]';line_cost=0;
  FOR stock IN SELECT batch_id,available_quantity,actual_unit_cost_mmk,received_at FROM app.pos_eligible_stock WHERE warehouse_id=warehouse AND product_id=product.id AND coalesce(x->>'stock_bucket','SELLABLE')='SELLABLE'
   UNION ALL SELECT batch_id,available_quantity,actual_unit_cost_mmk,received_at FROM app.pos_damaged_stock WHERE warehouse_id=warehouse AND product_id=product.id AND x->>'stock_bucket'='DAMAGED' AND batch_id=(x->>'batch_id')::uuid
   ORDER BY received_at,batch_id LOOP
   take=least(needed,stock.available_quantity);
   allocations=allocations||jsonb_build_array(jsonb_build_object('batch_id',stock.batch_id,'quantity',take::text,'unit_cost_mmk',stock.actual_unit_cost_mmk::text,'total_cost_mmk',round(take*stock.actual_unit_cost_mmk,4)::text));
   line_cost=line_cost+round(take*stock.actual_unit_cost_mmk,4);needed=needed-take;
   EXIT WHEN needed=0;
  END LOOP;
  IF needed>0 THEN RAISE EXCEPTION 'pos: Not enough unreserved, non-expired, costed stock. Refresh availability.' USING ERRCODE='23514'; END IF;
  line_total=round(qty*price-discount,4);
  needs_approval=needs_approval OR line_total<line_cost;
  total=total+line_total; costs=costs+line_cost;
  lines=lines||jsonb_build_array(jsonb_build_object('stock_bucket',coalesce(x->>'stock_bucket','SELLABLE'),'original_price_mmk',original_price::text,'product_id',product.id,'product_name',product.name,'sku',product.sku,'unit_code',pack.unit_code,'units_per_pack',pack.units_per_pack::text,'quantity',qty::text,'base_quantity',(qty*pack.units_per_pack)::text,'unit_price_mmk',price::text,'discount_mmk',discount::text,'total_mmk',line_total::text,'cost_mmk',line_cost::text,'allocations',allocations,'below_cost',line_total<line_cost));
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
  IF x->>'stock_bucket'='DAMAGED' THEN
   INSERT INTO app.damaged_products(product_id,batch_id,warehouse_id,quantity,estimated_loss_mmk,reason,occurred_at,recorded_by,disposition,original_price_mmk,reduced_price_mmk,sale_id,actual_unit_cost_mmk,discount_loss_mmk)
   VALUES((x->>'product_id')::uuid,(x->'allocations'->0->>'batch_id')::uuid,warehouse,(x->>'base_quantity')::numeric,greatest((x->>'cost_mmk')::numeric-(x->>'total_mmk')::numeric,0),d->>'reason',now(),actor,'REDUCED_PRICE',(x->>'original_price_mmk')::numeric,(x->>'unit_price_mmk')::numeric,sale,(x->'allocations'->0->>'unit_cost_mmk')::numeric,greatest(round((x->>'base_quantity')::numeric*(x->>'original_price_mmk')::numeric,4)-(x->>'total_mmk')::numeric,0));
  END IF;
  FOR alloc IN SELECT value FROM jsonb_array_elements(x->'allocations') LOOP
   INSERT INTO app.sale_item_batches(sale_item_id,batch_id,product_id,quantity,unit_cost_mmk) VALUES(sale_item,(alloc->>'batch_id')::uuid,(x->>'product_id')::uuid,(alloc->>'quantity')::numeric,(alloc->>'unit_cost_mmk')::numeric) RETURNING id INTO sale_batch;
   INSERT INTO app.inventory_movements(warehouse_id,batch_id,movement_type,sellable_delta,damaged_delta,unit_cost_mmk,sale_item_batch_id,idempotency_key,occurred_at,recorded_by,reason) VALUES(warehouse,(alloc->>'batch_id')::uuid,'SALE',CASE WHEN x->>'stock_bucket'='DAMAGED' THEN 0 ELSE -(alloc->>'quantity')::numeric END,CASE WHEN x->>'stock_bucket'='DAMAGED' THEN -(alloc->>'quantity')::numeric ELSE 0 END,(alloc->>'unit_cost_mmk')::numeric,sale_batch,'sale:'||sale_batch,now(),actor,invoice);
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
