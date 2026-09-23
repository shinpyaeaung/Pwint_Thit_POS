-- name: CreateCategory :one
INSERT INTO app.categories(name) VALUES($1) RETURNING id,name,is_active;
-- name: UpdateCategory :one
UPDATE app.categories SET name=$2,is_active=$3 WHERE id=$1 RETURNING id,name,is_active;
-- name: LockCategory :one
SELECT id,name,is_active FROM app.categories WHERE id=$1 FOR UPDATE;
-- name: CreateBrand :one
INSERT INTO app.brands(name) VALUES($1) RETURNING id,name,is_active;
-- name: UpdateBrand :one
UPDATE app.brands SET name=$2,is_active=$3 WHERE id=$1 RETURNING id,name,is_active;
-- name: LockBrand :one
SELECT id,name,is_active FROM app.brands WHERE id=$1 FOR UPDATE;
-- name: CreateCatalogUnit :one
INSERT INTO app.units(code,name) VALUES($1,$2) RETURNING code,name;
