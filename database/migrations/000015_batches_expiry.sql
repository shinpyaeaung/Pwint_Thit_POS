-- One business-date definition for alerts and POS eligibility, independent of server timezone.
CREATE FUNCTION app.business_date() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'Asia/Yangon')::date $$;
CREATE FUNCTION app.expiry_status(expiry date, as_of date) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN expiry IS NULL THEN 'NO_EXPIRY' WHEN expiry<as_of THEN 'EXPIRED' WHEN expiry<=as_of+30 THEN 'EXPIRING_30' WHEN expiry<=as_of+60 THEN 'EXPIRING_60' ELSE 'CURRENT' END
$$;
CREATE VIEW app.pos_eligible_stock AS
 SELECT i.*,b.product_id,b.received_at,b.expires_on,b.actual_unit_cost_mmk
 FROM app.inventory i JOIN app.batches b ON b.id=i.batch_id JOIN app.products p ON p.id=b.product_id
 WHERE i.available_quantity>0 AND b.finalized_at IS NOT NULL AND b.actual_unit_cost_mmk IS NOT NULL
 AND (b.expires_on IS NULL OR b.expires_on>=app.business_date())
 AND (NOT p.tracks_expiry OR b.expires_on IS NOT NULL);
