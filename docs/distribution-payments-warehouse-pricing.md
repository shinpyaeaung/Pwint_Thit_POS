# Distribution payments, warehouse prices and collection/delivery

## Business rules

- Product creation defines packaging and stock units; it adds no inventory. Product-level prices are optional defaults for later sales. Receiving purchased goods adds stock through immutable movements.
- Cargo-terminal transport charges and additional shipment costs remain separate from merchandise supplier invoices. The payment centre posts linked payments; it never changes a shipment's finalized landed costs.
- Warehouse prices are configured per product and packaging unit, with independent retail/wholesale values. This includes any home warehouse. Customer-specific prices take priority, then warehouse prices, then product defaults. No price is derived by dividing a carton selling price. Posted invoices retain their historical prices and FIFO costs.
- Damage, missing and discard entry accepts a configured unit. The backend validates the conversion and posts the exact base-unit movement. Individual-piece and mixed carton/piece sales continue to use transactional FIFO.
- Shipments record cargo-terminal delivery to the destination warehouse or collection from the terminal. Customer sales record customer collection or delivery by the business. Both offer an optional person/vehicle checkbox. Shipments and invoices without recorded details display as unspecified. The follow-up migration preserves existing values, including delivery defaults already assigned by migration 000029, and removes that database default for subsequent records. These details do not create charges or stock movements; shipment details lock under existing finalization controls and sale details are included in immutable invoice snapshots.

## Screens

- **Payments → Payment centre** has Supplier Payments, Customer Payments and Transportation Payments categories, filtered by the user's existing backend permissions. Existing source-page payment entry remains available and uses the same ledgers.
- Supplier payments link to purchases; customer payments link to invoices; transportation payments link to the cargo-terminal stage or separate additional-cost record and its shipment. Partial/full payments and histories are available centrally. Cancelling logistics does not erase incurred cargo charges: cancelled shipments remain labelled in the payment centre; voided additional costs are excluded.
- Transportation methods reuse the configurable named methods. Transportation charges settle in MMK; foreign-currency additional costs settle in their original currency using the charge's historical rate. Supplier settlement rules remain unchanged.
- **Products & stock → Warehouse prices** allows prices to be set before stock arrives. The POS Prices button now sets prices for its selected warehouse.
- **Damage & missing → Record issue → Issue unit** accepts cartons or individual units and previews the base units affected.
- Shipment creation/edit and POS checkout expose collection/delivery selection and optional person/vehicle details. Shipment summaries and invoices display the saved details.

## Implementation and integrity

Migrations 000029–000031 add warehouse price configuration, shipment fulfillment details and retry-safe transport payments. Existing payment/allocation tables are reused. Cargo payments serialize against the shipment lock used by cost editing, preventing concurrent overpayment or payment/void races. Payment, allocation, retry and audit writes share one explicit transaction. Posted payment records remain immutable.

Warehouse price changes use product versions, locks and audit snapshots. Checkout validates current effective prices and binds fulfillment details into its quote. Damage conversion is server-validated after the idempotency check, so retries return the original result even after stock changes.
