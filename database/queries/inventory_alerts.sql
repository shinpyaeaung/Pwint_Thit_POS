-- name: InventoryAlerts :one
WITH quantities AS (
 SELECT product_id,sum(available_quantity) AS available FROM app.pos_eligible_stock
 WHERE sqlc.narg(warehouse_id)::uuid IS NULL OR warehouse_id=sqlc.narg(warehouse_id) GROUP BY product_id
), filtered AS (
 SELECT p.id AS product_id,p.name AS product_name,p.sku,p.base_unit_code AS unit,p.minimum_stock,coalesce(q.available,0) AS available
 FROM app.products p LEFT JOIN quantities q ON q.product_id=p.id
 WHERE p.is_active AND (sqlc.arg(search)::text='' OR strpos(lower(p.name||' '||p.sku),lower(sqlc.arg(search)))>0)
 AND CASE sqlc.arg(stock_status)::text WHEN 'out' THEN coalesce(q.available,0)=0 WHEN 'low' THEN q.available>0 AND q.available<=p.minimum_stock ELSE false END
), page AS (SELECT * FROM filtered ORDER BY product_name,product_id LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'products',coalesce((SELECT jsonb_agg(app.report_decimal_row(to_jsonb(page)) ORDER BY product_name,product_id) FROM page),'[]'))::jsonb;
