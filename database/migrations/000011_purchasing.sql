ALTER TABLE app.purchases ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.purchases ADD COLUMN request_hash text;
ALTER TABLE app.purchases ADD CONSTRAINT purchase_request_pair CHECK((request_id IS NULL)=(request_hash IS NULL));
ALTER TABLE app.purchase_items ADD COLUMN product_name_snapshot text;
ALTER TABLE app.purchase_items ADD COLUMN sku_snapshot text;
ALTER TABLE app.purchase_items ADD COLUMN unit_name_snapshot text;
CREATE TABLE app.purchase_amounts (
 purchase_id uuid PRIMARY KEY REFERENCES app.purchases(id),
 currency_code text NOT NULL REFERENCES app.currencies(code),
 mmk_per_unit numeric(24,10) NOT NULL CHECK(mmk_per_unit>0 AND mmk_per_unit<>'NaN'::numeric),
 amount_original numeric(20,4) NOT NULL CHECK(amount_original>=0 AND amount_original<>'NaN'::numeric),
 amount_mmk numeric(20,4) GENERATED ALWAYS AS (round(amount_original*mmk_per_unit,4)) STORED,
 created_at timestamptz NOT NULL DEFAULT now()
);
-- Preserve existing posted documents without updating any historical transaction.
INSERT INTO app.purchase_amounts(purchase_id,currency_code,mmk_per_unit,amount_original)
SELECT p.id,p.currency_code,p.mmk_per_unit,t.total_original FROM app.purchases p JOIN app.purchase_totals t ON t.purchase_id=p.id WHERE p.posted_at IS NOT NULL;
CREATE TRIGGER purchase_amounts_immutable BEFORE UPDATE OR DELETE ON app.purchase_amounts FOR EACH ROW EXECUTE FUNCTION app.deny_mutation();
CREATE FUNCTION app.snapshot_purchase_amounts() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.status='POSTED' AND (TG_OP='INSERT' OR OLD.status<>'POSTED') THEN
  IF NOT EXISTS(SELECT 1 FROM app.purchase_items WHERE purchase_id=NEW.id) THEN RAISE EXCEPTION 'purchase requires items before posting' USING ERRCODE='23514'; END IF;
  INSERT INTO app.purchase_amounts(purchase_id,currency_code,mmk_per_unit,amount_original)
  SELECT NEW.id,NEW.currency_code,NEW.mmk_per_unit,sum(total_original) FROM app.purchase_items WHERE purchase_id=NEW.id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER purchase_amount_snapshot AFTER INSERT OR UPDATE ON app.purchases FOR EACH ROW EXECUTE FUNCTION app.snapshot_purchase_amounts();
CREATE INDEX purchase_list_page ON app.purchases(purchased_at DESC,id);
CREATE FUNCTION app.purchase_document(p app.purchases, costs boolean, details boolean) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',p.id,'purchase_number',p.purchase_number,'supplier_id',p.supplier_id,
 'supplier_name',(SELECT name FROM app.suppliers WHERE id=p.supplier_id),'supplier_invoice_number',p.supplier_invoice_number,
 'purchased_at',p.purchased_at,'due_date',p.due_date,'status',p.status,'currency_code',p.currency_code,'notes',p.notes,'created_at',p.created_at,
 'can_view_cost',costs)
 || CASE WHEN costs THEN jsonb_build_object('mmk_per_unit',p.mmk_per_unit::text,'exchange_rate_id',p.exchange_rate_id,
 'total_original',COALESCE(a.amount_original,t.total_original)::text,'total_mmk',COALESCE(a.amount_mmk,t.total_mmk)::text,
 'amount_paid_mmk',b.amount_paid_mmk::text,'outstanding_original',b.outstanding_original::text,'outstanding_mmk',b.outstanding_mmk::text,'payment_status',b.payment_status) ELSE '{}'::jsonb END
 || CASE WHEN details THEN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',i.id,'product_id',i.product_id,'product_name',COALESCE(i.product_name_snapshot,pr.name),'sku',COALESCE(i.sku_snapshot,pr.sku),'unit_code',i.unit_code,'unit_name',COALESCE(i.unit_name_snapshot,u.name),'quantity',i.quantity::text,'units_per_pack',i.units_per_pack::text,'base_quantity',i.base_quantity::text)
 || CASE WHEN costs THEN jsonb_build_object('unit_price_original',i.unit_price_original::text,'discount_original',i.discount_original::text,'tax_original',i.tax_original::text,'total_original',i.total_original::text) ELSE '{}'::jsonb END ORDER BY i.line_number) FROM app.purchase_items i JOIN app.products pr ON pr.id=i.product_id JOIN app.units u ON u.code=i.unit_code WHERE i.purchase_id=p.id),'[]'::jsonb)) ELSE '{}'::jsonb END
 FROM app.purchase_totals t LEFT JOIN app.purchase_amounts a ON a.purchase_id=t.purchase_id LEFT JOIN app.supplier_payables b ON b.purchase_id=t.purchase_id WHERE t.purchase_id=p.id
$$;
