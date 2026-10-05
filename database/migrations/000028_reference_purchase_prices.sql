-- Optional catalog defaults, never a replacement for transaction or batch costs.
ALTER TABLE app.product_units ADD COLUMN purchase_price_mmk numeric(20,4)
 CHECK(purchase_price_mmk>=0 AND purchase_price_mmk<>'NaN'::numeric);
DO $$ DECLARE definition text;
BEGIN
 definition=pg_get_functiondef('app.product_document(app.products)'::regprocedure);
 definition=replace(definition,'''retail_price_mmk'',u.retail_price_mmk::text', '''purchase_price_mmk'',u.purchase_price_mmk::text,''retail_price_mmk'',u.retail_price_mmk::text');
 IF strpos(definition,'''purchase_price_mmk''')=0 THEN RAISE EXCEPTION 'Unexpected product document definition'; END IF;
 EXECUTE definition;
END $$;
CREATE INDEX supplier_payment_purchase_history ON app.payment_allocations(purchase_id,payment_id) WHERE purchase_id IS NOT NULL;
