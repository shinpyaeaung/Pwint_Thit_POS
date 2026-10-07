-- Preserve installed migration checksums and existing recorded fulfillment values.
-- Missing details may remain unknown; never infer delivery for subsequent imports.
ALTER TABLE app.shipments ALTER COLUMN fulfillment DROP NOT NULL;
ALTER TABLE app.shipments ALTER COLUMN fulfillment DROP DEFAULT;
ALTER TABLE app.shipments DROP CONSTRAINT shipment_fulfillment_valid;
ALTER TABLE app.shipments ADD CONSTRAINT shipment_fulfillment_valid
 CHECK(fulfillment IS NULL OR app.valid_fulfillment(fulfillment));
