-- name: RecordSupplierPayment :one
SELECT app.record_supplier_payment(sqlc.arg(purchase_id)::uuid,sqlc.arg(actor)::uuid,sqlc.arg(data)::jsonb)::uuid;
-- name: SupplierPaymentMethods :one
SELECT COALESCE(jsonb_agg(to_jsonb(m) ORDER BY name),'[]'::jsonb)::jsonb FROM app.supplier_payment_methods m;
-- name: AddSupplierPaymentMethod :exec
INSERT INTO app.supplier_payment_methods(code,name,category) VALUES($1,$2,$3);
-- name: SupplierPaymentHistory :one
SELECT jsonb_build_object('payments',COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'payment_number',p.payment_number,'amount',p.amount_original::text,'currency_code',p.currency_code,'amount_mmk',p.amount_mmk::text,'method',COALESCE(p.method_name_snapshot,p.method),'bank_account',p.bank_account,'paid_at',p.paid_at,'reference_number',p.reference_number,'notes',p.notes,'status',p.status,'created_at',p.created_at,'created_by',u.display_name) ORDER BY p.paid_at,p.created_at),'[]'::jsonb))::jsonb
FROM app.payments p JOIN app.payment_allocations a ON a.payment_id=p.id JOIN app.users u ON u.id=p.recorded_by WHERE a.purchase_id=$1;
-- name: SupplierPaymentPurchases :one
WITH filtered AS (
 SELECT p.* FROM app.purchases p JOIN app.supplier_payables b ON b.purchase_id=p.id JOIN app.suppliers s ON s.id=p.supplier_id
 WHERE (sqlc.arg(search)::text='' OR strpos(lower(p.purchase_number||' '||s.name),lower(sqlc.arg(search)))>0)
 AND (sqlc.arg(payment_status)::text='' OR CASE WHEN b.outstanding_original<=0 THEN 'PAID' WHEN b.amount_paid_mmk>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END=sqlc.arg(payment_status))
), page AS (SELECT * FROM filtered ORDER BY purchased_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'purchases',COALESCE((SELECT jsonb_agg(app.purchase_document(p,true,false) ORDER BY p.purchased_at DESC,p.id) FROM app.purchases p JOIN page f USING(id)),'[]'::jsonb))::jsonb;
