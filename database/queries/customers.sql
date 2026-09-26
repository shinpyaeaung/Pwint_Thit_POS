-- name: CustomerSave :one
SELECT app.customer_save(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: CustomerPrice :exec
SELECT app.customer_price(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid);
-- name: CustomerPayment :one
SELECT app.customer_payment(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: CustomerPrices :one
SELECT coalesce(jsonb_agg(jsonb_build_object('product_id',p.product_id,'product_name',pr.name,'sku',pr.sku,'unit_code',p.unit_code,'price_mmk',p.price_mmk::text) ORDER BY pr.name,p.unit_code),'[]'::jsonb)::jsonb FROM app.customer_prices p JOIN app.products pr ON pr.id=p.product_id WHERE p.customer_id=sqlc.arg(id)::uuid;
-- name: CustomersList :one
WITH filtered AS (SELECT c.id,c.code,c.name,c.phone,c.customer_type,c.is_active,c.credit_limit_mmk::text AS credit_limit_mmk,
 coalesce((SELECT sum(greatest(outstanding_mmk,0)) FROM app.customer_debts d WHERE d.customer_id=c.id),0)::text AS outstanding_mmk
 FROM app.customers c WHERE (sqlc.arg(search)::text='' OR strpos(lower(c.code||' '||c.name||' '||coalesce(c.phone,'')),lower(sqlc.arg(search)))>0)
 AND (sqlc.arg(kind)::text='' OR c.customer_type=sqlc.arg(kind))
 AND (sqlc.arg(status)::text='' OR c.is_active=(sqlc.arg(status)='ACTIVE'))), page AS (SELECT * FROM filtered ORDER BY name,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'customers',coalesce((SELECT jsonb_agg(to_jsonb(page) ORDER BY name,id) FROM page),'[]'))::jsonb;
-- name: CustomerDetail :one
SELECT (to_jsonb(c)||jsonb_build_object('version',c.version::text,'credit_limit_mmk',c.credit_limit_mmk::text,
 'outstanding_mmk',coalesce((SELECT sum(greatest(outstanding_mmk,0)) FROM app.customer_debts d WHERE d.customer_id=c.id),0)::text,
 'credit_mmk',coalesce((SELECT sum(greatest(-outstanding_mmk,0)) FROM app.customer_debts d WHERE d.customer_id=c.id),0)::text))::jsonb
FROM app.customers c WHERE id=sqlc.arg(id)::uuid;
-- name: CustomerHistory :one
WITH filtered AS (SELECT s.id,s.invoice_number,s.sold_at,d.due_date,d.total_mmk::text AS total_mmk,d.amount_paid_mmk::text AS amount_paid_mmk,d.return_credit_mmk::text AS return_credit_mmk,d.refunded_mmk::text AS refunded_mmk,d.outstanding_mmk::text AS outstanding_mmk,d.payment_status
 FROM app.sales s JOIN app.customer_debts d ON d.sale_id=s.id WHERE s.customer_id=sqlc.arg(id)::uuid), page AS (SELECT * FROM filtered ORDER BY sold_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'invoices',coalesce((SELECT jsonb_agg(to_jsonb(page) ORDER BY sold_at DESC,id) FROM page),'[]'))::jsonb;
-- name: CustomerPayments :one
SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY paid_at DESC,id),'[]'::jsonb)::jsonb FROM (SELECT p.id,p.payment_number,p.paid_at,p.direction,p.method,p.amount_mmk::text,p.reference_number,s.invoice_number FROM app.payments p LEFT JOIN app.payment_allocations a ON a.payment_id=p.id LEFT JOIN app.sales s ON s.id=a.sale_id WHERE p.customer_id=sqlc.arg(id)::uuid AND p.status='POSTED' ORDER BY p.paid_at DESC,p.id LIMIT 200) x;
-- name: CustomerCatalog :one
SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)::jsonb FROM (SELECT p.id,p.name,p.sku,(SELECT jsonb_agg(u.unit_code ORDER BY u.unit_code) FROM app.product_units u WHERE u.product_id=p.id) AS units FROM app.products p WHERE p.is_active AND p.archived_at IS NULL AND (sqlc.arg(search)::text='' OR strpos(lower(p.name||' '||p.sku),lower(sqlc.arg(search)))>0) ORDER BY p.name,p.id LIMIT 50) x;
