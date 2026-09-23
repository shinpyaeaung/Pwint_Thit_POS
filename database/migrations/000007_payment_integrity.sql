-- Validate parties and settlement direction at the database boundary as well as in later services.
CREATE FUNCTION app.validate_payment_allocation() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p app.payments%ROWTYPE; party uuid; expected_direction text; rate numeric; original_currency text;
BEGIN
 SELECT * INTO p FROM app.payments WHERE id=NEW.payment_id FOR UPDATE;
 IF NEW.sale_id IS NOT NULL THEN
  SELECT customer_id INTO party FROM app.sales WHERE id=NEW.sale_id;
  IF p.customer_id IS DISTINCT FROM party OR p.supplier_id IS NOT NULL THEN RAISE EXCEPTION 'sale payment customer mismatch' USING ERRCODE='23514'; END IF;
  expected_direction='IN'; rate=1;
 ELSIF NEW.purchase_id IS NOT NULL THEN
  SELECT supplier_id,mmk_per_unit INTO party,rate FROM app.purchases WHERE id=NEW.purchase_id;
  IF p.supplier_id IS DISTINCT FROM party OR p.customer_id IS NOT NULL THEN RAISE EXCEPTION 'purchase payment supplier mismatch' USING ERRCODE='23514'; END IF;
  expected_direction='OUT';
 ELSIF NEW.sales_return_id IS NOT NULL THEN
  SELECT s.customer_id INTO party FROM app.sales s JOIN app.sales_returns r ON r.sale_id=s.id WHERE r.id=NEW.sales_return_id;
  IF p.customer_id IS DISTINCT FROM party OR p.supplier_id IS NOT NULL THEN RAISE EXCEPTION 'refund customer mismatch' USING ERRCODE='23514'; END IF;
  expected_direction='OUT'; rate=1;
 ELSIF NEW.purchase_return_id IS NOT NULL THEN
  SELECT s.supplier_id,s.mmk_per_unit INTO party,rate FROM app.purchases s JOIN app.purchase_returns r ON r.purchase_id=s.id WHERE r.id=NEW.purchase_return_id;
  IF p.supplier_id IS DISTINCT FROM party OR p.customer_id IS NOT NULL THEN RAISE EXCEPTION 'refund supplier mismatch' USING ERRCODE='23514'; END IF;
  expected_direction='IN';
 ELSE
  expected_direction='OUT';
  IF p.customer_id IS NOT NULL OR p.supplier_id IS NOT NULL THEN RAISE EXCEPTION 'expense settlement cannot name customer or merchandise supplier' USING ERRCODE='23514'; END IF;
  IF NEW.expense_id IS NOT NULL THEN SELECT mmk_per_unit INTO rate FROM app.expenses WHERE id=NEW.expense_id;
  ELSIF NEW.shipment_expense_id IS NOT NULL THEN SELECT mmk_per_unit INTO rate FROM app.shipment_expenses WHERE id=NEW.shipment_expense_id;
  ELSE rate=1; END IF;
 END IF;
 IF p.direction<>expected_direction THEN RAISE EXCEPTION 'payment direction mismatch' USING ERRCODE='23514'; END IF;
 IF NEW.applied_mmk<>round(NEW.applied_original*rate,4) THEN RAISE EXCEPTION 'allocation must use original document exchange rate' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_allocation BEFORE INSERT OR UPDATE ON app.payment_allocations FOR EACH ROW EXECUTE FUNCTION app.validate_payment_allocation();

CREATE FUNCTION app.validate_payment_posting() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE total numeric; original app.payments%ROWTYPE;
BEGIN
 IF NEW.status='POSTED' AND (TG_OP='INSERT' OR OLD.status<>'POSTED') THEN
  IF NEW.reverses_payment_id IS NOT NULL THEN
   SELECT * INTO original FROM app.payments WHERE id=NEW.reverses_payment_id FOR UPDATE;
   IF original.status<>'REVERSED' OR NEW.direction=original.direction OR NEW.currency_code<>original.currency_code
    OR NEW.amount_original<>original.amount_original OR NEW.mmk_per_unit<>original.mmk_per_unit
    OR NEW.customer_id IS DISTINCT FROM original.customer_id OR NEW.supplier_id IS DISTINCT FROM original.supplier_id THEN
    RAISE EXCEPTION 'invalid payment reversal' USING ERRCODE='23514'; END IF;
   IF EXISTS(SELECT 1 FROM app.payment_allocations WHERE payment_id=NEW.id) THEN RAISE EXCEPTION 'reversal uses original allocation history' USING ERRCODE='23514'; END IF;
  ELSE
   SELECT COALESCE(sum(settlement_mmk),0) INTO total FROM app.payment_allocations WHERE payment_id=NEW.id;
   IF total>round(NEW.amount_original*NEW.mmk_per_unit,4) THEN RAISE EXCEPTION 'allocations exceed payment amount' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 -- Changing party/direction/rate after entering allocations would invalidate their checks.
 IF TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM app.payment_allocations WHERE payment_id=OLD.id)
 AND (NEW.customer_id IS DISTINCT FROM OLD.customer_id OR NEW.supplier_id IS DISTINCT FROM OLD.supplier_id OR NEW.direction<>OLD.direction
 OR NEW.currency_code<>OLD.currency_code OR NEW.mmk_per_unit<>OLD.mmk_per_unit OR NEW.reverses_payment_id IS DISTINCT FROM OLD.reverses_payment_id) THEN
  RAISE EXCEPTION 'remove draft allocations before changing payment identity' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_payment BEFORE INSERT OR UPDATE ON app.payments FOR EACH ROW EXECUTE FUNCTION app.validate_payment_posting();

ALTER TABLE app.sale_item_batches ADD UNIQUE(id,batch_id);
ALTER TABLE app.batches ADD UNIQUE(receiving_item_id,id);
ALTER TABLE app.inventory_movements ADD FOREIGN KEY(sale_item_batch_id,batch_id) REFERENCES app.sale_item_batches(id,batch_id);
ALTER TABLE app.inventory_movements ADD FOREIGN KEY(receiving_item_id,batch_id) REFERENCES app.batches(receiving_item_id,id);
CREATE INDEX inventory_movements_sale_batch ON app.inventory_movements(sale_item_batch_id,batch_id);
CREATE INDEX inventory_movements_receiving_batch ON app.inventory_movements(receiving_item_id,batch_id);
