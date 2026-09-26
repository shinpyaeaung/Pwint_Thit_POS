INSERT INTO app.expense_categories(name) VALUES('Rent'),('Salaries'),('Electricity'),('Internet'),('Fuel'),('Marketing'),('Warehouse expenses'),('Maintenance'),('Other operating expenses') ON CONFLICT(name) DO NOTHING;
ALTER TABLE app.expenses ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.expenses ADD COLUMN request_payload jsonb;
CREATE TABLE app.expense_reversals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),expense_id uuid NOT NULL UNIQUE REFERENCES app.expenses(id),
 request_id uuid NOT NULL UNIQUE,request_payload jsonb NOT NULL,reason text NOT NULL CHECK(btrim(reason)<>''),
 recorded_by uuid NOT NULL REFERENCES app.users(id),reversed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX expense_reversals_actor ON app.expense_reversals(recorded_by);
CREATE INDEX expense_reversals_date ON app.expense_reversals(reversed_at);
CREATE TRIGGER expense_reversal_immutable BEFORE UPDATE OR DELETE ON app.expense_reversals FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
-- Expense corrections use immutable linked offsets; existing document guards stay intact.
CREATE TABLE app.expense_reversal_payments (
 reversal_id uuid NOT NULL REFERENCES app.expense_reversals(id),
 original_payment_id uuid PRIMARY KEY REFERENCES app.payments(id),
 offset_payment_id uuid NOT NULL UNIQUE REFERENCES app.payments(id),
 CHECK(original_payment_id<>offset_payment_id)
);
CREATE INDEX expense_reversal_payments_reversal ON app.expense_reversal_payments(reversal_id);
CREATE TRIGGER expense_reversal_payment_immutable BEFORE UPDATE OR DELETE ON app.expense_reversal_payments FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE FUNCTION app.expense_post(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.expenses; expense uuid; payment uuid; incurred date=(d->>'incurred_on')::date; value numeric=(d->>'amount_mmk')::numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.expenses WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF old.recorded_by<>actor OR old.request_payload<>d THEN RAISE EXCEPTION 'finance: Request already used with different details.' USING ERRCODE='23514'; END IF;RETURN old.id;END IF;
 IF incurred>app.business_date() OR value<=0 THEN RAISE EXCEPTION 'finance: Enter a positive expense incurred on or before today.' USING ERRCODE='23514';END IF;
 INSERT INTO app.expenses(category_id,description,incurred_at,currency_code,amount_original,mmk_per_unit,recorded_by,notes,request_id,request_payload)
 VALUES((d->>'category_id')::uuid,d->>'description',incurred::timestamp AT TIME ZONE 'Asia/Yangon','MMK',value,1,actor,d->>'notes',(d->>'request_id')::uuid,d) RETURNING id INTO expense;
 IF (d->>'paid_now')::boolean THEN
  INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,paid_at,reference_number,recorded_by) VALUES('EXP-'||expense,'OUT',d->>'method','MMK',value,1,now(),d->>'reference',actor) RETURNING id INTO payment;
  INSERT INTO app.payment_allocations(payment_id,expense_id,settlement_mmk,applied_mmk,applied_original) VALUES(payment,expense,value,value,value);
  UPDATE app.payments SET status='POSTED',posted_at=now() WHERE id=payment;
 END IF;
 UPDATE app.expenses SET status='POSTED',posted_at=now() WHERE id=expense;
 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,new_value) VALUES(actor,'expenses.post','expenses',expense,d);
 RETURN expense;
END $$;
CREATE FUNCTION app.expense_reverse(d jsonb,actor uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE old app.expense_reversals; e app.expenses;p app.payments;result uuid;offset_payment uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(d->>'request_id',0));
 SELECT * INTO old FROM app.expense_reversals WHERE request_id=(d->>'request_id')::uuid;
 IF FOUND THEN IF old.recorded_by<>actor OR old.request_payload<>d THEN RAISE EXCEPTION 'finance: Reversal request already used.' USING ERRCODE='23514';END IF;RETURN old.id;END IF;
 SELECT * INTO e FROM app.expenses WHERE id=(d->>'expense_id')::uuid FOR UPDATE;
 IF NOT FOUND OR e.status<>'POSTED' OR EXISTS(SELECT 1 FROM app.expense_reversals WHERE expense_id=e.id) THEN RAISE EXCEPTION 'finance: Only a posted expense can be reversed once.' USING ERRCODE='23514';END IF;
 INSERT INTO app.expense_reversals(expense_id,request_id,request_payload,reason,recorded_by) VALUES(e.id,(d->>'request_id')::uuid,d,d->>'reason',actor) RETURNING id INTO result;
 FOR p IN SELECT pay.* FROM app.payments pay JOIN app.payment_allocations a ON a.payment_id=pay.id WHERE a.expense_id=e.id AND pay.status='POSTED' ORDER BY pay.id FOR UPDATE OF pay LOOP
  IF (SELECT count(*) FROM app.payment_allocations WHERE payment_id=p.id)<>1 THEN RAISE EXCEPTION 'finance: Shared payments require a separate payment reversal.' USING ERRCODE='23514';END IF;
  INSERT INTO app.payments(payment_number,direction,method,currency_code,amount_original,mmk_per_unit,paid_at,reference_number,recorded_by,status,posted_at)
  VALUES('REV-'||p.id,'IN',p.method,p.currency_code,p.amount_original,p.mmk_per_unit,now(),d->>'reason',actor,'POSTED',now()) RETURNING id INTO offset_payment;
  INSERT INTO app.expense_reversal_payments(reversal_id,original_payment_id,offset_payment_id) VALUES(result,p.id,offset_payment);
 END LOOP;

 INSERT INTO app.audit_logs(actor_id,action,entity_type,entity_id,old_value,new_value,reason) VALUES(actor,'expenses.reverse','expenses',e.id,to_jsonb(e),jsonb_build_object('reversal_id',result),d->>'reason');
 RETURN result;
END $$;
-- Sales/returns are accrual events, independent of payment collection or cash refunds.
CREATE VIEW app.profit_sales_events AS
 WITH returned AS (
  SELECT r.id,r.returned_at,i.refund_mmk,b.unit_cost_mmk,
   sum(i.quantity) OVER(PARTITION BY b.id ORDER BY r.returned_at,r.id,i.id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS through_quantity,
   coalesce(sum(i.quantity) OVER(PARTITION BY b.id ORDER BY r.returned_at,r.id,i.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) AS prior_quantity
  FROM app.sales_returns r JOIN app.sales_return_items i ON i.sales_return_id=r.id JOIN app.sale_item_batches b ON b.id=i.sale_item_batch_id WHERE r.status='POSTED'
 )
 SELECT s.id,s.sold_at AS occurred_at,t.total_mmk AS revenue_mmk,
 coalesce((SELECT sum(b.total_cost_mmk) FROM app.sale_item_batches b JOIN app.sale_items i ON i.id=b.sale_item_id WHERE i.sale_id=s.id),0)::numeric AS cogs_mmk,
 EXISTS(SELECT 1 FROM app.sale_items i WHERE i.sale_id=s.id AND i.base_quantity<>(SELECT coalesce(sum(b.quantity),0) FROM app.sale_item_batches b WHERE b.sale_item_id=i.id)) AS incomplete_cost,
 'SALE'::text AS event_type
 FROM app.sales s JOIN app.sale_totals t ON t.sale_id=s.id WHERE s.status='POSTED'
 UNION ALL
 SELECT id,returned_at,-sum(refund_mmk),-sum(round(through_quantity*unit_cost_mmk,4)-round(prior_quantity*unit_cost_mmk,4)),false,'RETURN' FROM returned GROUP BY id,returned_at;
CREATE VIEW app.profit_expense_events AS
 SELECT e.id,e.category_id,e.incurred_at AS occurred_at,e.amount_mmk FROM app.expenses e WHERE e.status IN('POSTED','REVERSED')
 UNION ALL SELECT r.id,e.category_id,r.reversed_at,-e.amount_mmk FROM app.expense_reversals r JOIN app.expenses e ON e.id=r.expense_id;
CREATE FUNCTION app.profit_summary(start_on date,end_on date) RETURNS jsonb LANGUAGE sql STABLE AS $$
 WITH sales AS(SELECT coalesce(sum(revenue_mmk),0) revenue,coalesce(sum(cogs_mmk),0) cogs,count(*) FILTER(WHERE incomplete_cost) missing,
 coalesce(sum(revenue_mmk) FILTER(WHERE event_type='SALE'),0) sold,coalesce(-sum(revenue_mmk) FILTER(WHERE event_type='RETURN'),0) returned
 FROM app.profit_sales_events WHERE occurred_at>=start_on::timestamp AT TIME ZONE 'Asia/Yangon' AND occurred_at<(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon'),
 expenses AS(SELECT coalesce(sum(amount_mmk),0) amount FROM app.profit_expense_events WHERE occurred_at>=start_on::timestamp AT TIME ZONE 'Asia/Yangon' AND occurred_at<(end_on+1)::timestamp AT TIME ZONE 'Asia/Yangon')
 SELECT jsonb_build_object('from',start_on,'to',end_on,'sales_mmk',round(sold,4)::text,'returns_mmk',round(returned,4)::text,'revenue_mmk',round(revenue,4)::text,'cogs_mmk',round(cogs,4)::text,'expenses_mmk',round(amount,4)::text,'gross_profit_mmk',CASE WHEN missing=0 THEN round(revenue-cogs,4)::text END,'net_profit_mmk',CASE WHEN missing=0 THEN round(revenue-cogs-amount,4)::text END,'incomplete_cost_sales',missing)
 FROM sales CROSS JOIN expenses
$$;
