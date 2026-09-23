-- name: ListSuppliers :one
WITH filtered AS (
 SELECT s.* FROM app.suppliers s WHERE
 (CASE sqlc.arg(status)::text WHEN 'archived' THEN s.archived_at IS NOT NULL WHEN 'active' THEN s.archived_at IS NULL AND s.is_active WHEN 'inactive' THEN s.archived_at IS NULL AND NOT s.is_active ELSE s.archived_at IS NULL END)
 AND (sqlc.arg(country)::text='' OR s.country_code=sqlc.arg(country))
 AND (sqlc.arg(search)::text='' OR strpos(lower(s.name),lower(sqlc.arg(search)))>0 OR strpos(lower(s.code),lower(sqlc.arg(search)))>0 OR strpos(lower(COALESCE(s.contact_person,'')),lower(sqlc.arg(search)))>0 OR strpos(COALESCE(s.phone,''),sqlc.arg(search))>0)
), page AS (SELECT * FROM filtered ORDER BY created_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'suppliers',COALESCE((SELECT jsonb_agg(app.supplier_document(s) ORDER BY s.created_at DESC,s.id) FROM app.suppliers s JOIN page f USING(id)),'[]'::jsonb))::jsonb;
-- name: GetSupplier :one
SELECT app.supplier_document(s)::jsonb FROM app.suppliers s WHERE id=$1;
-- name: LockSupplier :one
SELECT id,version,archived_at FROM app.suppliers WHERE id=$1 FOR UPDATE;
-- name: ArchiveSupplier :exec
UPDATE app.suppliers SET is_active=false,archived_at=clock_timestamp() WHERE id=$1;
-- name: InsertSupplier :one
INSERT INTO app.suppliers(code,name,contact_person,phone,address,country_code,supplier_type,payment_terms,notes,is_active)
SELECT d->>'code',d->>'name',NULLIF(d->>'contact_person',''),NULLIF(d->>'phone',''),NULLIF(d->>'address',''),NULLIF(d->>'country_code',''),NULLIF(d->>'supplier_type',''),NULLIF(d->>'payment_terms',''),NULLIF(d->>'notes',''),(d->>'is_active')::boolean FROM (SELECT sqlc.arg(data)::jsonb d) t RETURNING id;
-- name: UpdateSupplier :exec
UPDATE app.suppliers SET code=d->>'code',name=d->>'name',contact_person=NULLIF(d->>'contact_person',''),phone=NULLIF(d->>'phone',''),address=NULLIF(d->>'address',''),country_code=NULLIF(d->>'country_code',''),supplier_type=NULLIF(d->>'supplier_type',''),payment_terms=NULLIF(d->>'payment_terms',''),notes=NULLIF(d->>'notes',''),is_active=(d->>'is_active')::boolean FROM (SELECT sqlc.arg(data)::jsonb d) t WHERE id=sqlc.arg(id);
-- name: SupplierPurchaseHistory :one
WITH filtered AS (SELECT * FROM app.purchases WHERE supplier_id=sqlc.arg(supplier_id)),
page AS (SELECT * FROM filtered ORDER BY purchased_at DESC,id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'can_view_cost',sqlc.arg(view_cost)::boolean,'purchases',COALESCE((SELECT jsonb_agg(
 jsonb_build_object('id',p.id,'purchase_number',p.purchase_number,'supplier_invoice_number',p.supplier_invoice_number,'purchased_at',p.purchased_at,'due_date',p.due_date,'status',p.status,'currency_code',p.currency_code,'item_count',(SELECT count(*) FROM app.purchase_items i WHERE i.purchase_id=p.id))
 || CASE WHEN sqlc.arg(view_cost)::boolean THEN jsonb_build_object('total_original',(SELECT COALESCE(sum(i.total_original),0)::text FROM app.purchase_items i WHERE i.purchase_id=p.id)) ELSE '{}'::jsonb END
 ORDER BY p.purchased_at DESC,p.id) FROM page p),'[]'::jsonb))::jsonb;
