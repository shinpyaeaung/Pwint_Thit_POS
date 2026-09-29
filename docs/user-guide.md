# Pwint Thit — User guide

Open **User guide** at the bottom of the sidebar, or visit `/guide` after signing in. Dashboard (`/dashboard`) and Reports (`/reports`) are pinned at the top for users with access.

## 1. Find your tools

Dashboard and Reports stay at the top of the sidebar. Scroll inside the menu to reach the remaining tools. On a phone or narrow window, use the menu button at the top left.

User guide stays at the bottom of the menu. System status and UI library are developer tools, so they are not part of the daily business menu.

Start with suppliers and products, then record purchases, shipments, landed costs and receiving. Goods become available for sale only after receiving. A purchase alone does not add sellable stock.

## 2. Set up products and suppliers

Use Catalog setup to define categories, brands and units. In Products, enter the name, SKU or barcode, base unit and packaging conversions. For example, one carton may contain 12 bottles. Check conversions before recording purchases or sales.

Use Suppliers to add supplier names, contact details and payment terms. Currency & rates opens the currency settings when your account has exchange-rate access.

Archive or deactivate unused records instead of removing their business history.

## 3. Purchase, transport and receive

In Purchases, choose a supplier, purchase date, currency and transaction exchange rate. Add products, quantities, units and original-currency prices. Review the original and MMK totals before posting.

In Shipments, select purchased goods and the destination warehouse. Add transportation stages and shipment expenses. Record departure and arrival as the goods move.

Open the shipment’s Landed cost section. Choose an allocation method and confirm expected sellable quantities, allowing for damage or missing goods. Preview and review the costs before finalizing. Finalized costing is preserved as history.

Use Goods receiving for arrived, cost-finalized shipments. Enter received cartons or units, damage, batch numbers and expiry dates. Receiving must reconcile with the confirmed sellable quantities. Posting creates stock movements and batch inventory.

## 4. Check inventory and expiry

Inventory shows stock by warehouse and batch, including sellable, reserved, available and damaged quantities. Use Batches & expiry to inspect batch history and expiry warnings.

Available stock is sellable stock minus reservations. Expired or incompletely costed goods may be physically present but cannot be sold through normal POS.

When an authorized correction is needed, use the stock adjustment workflow and record a reason. Never edit database stock totals directly.

## 5. Make a sale and review the invoice

Choose the warehouse and, where needed, a customer. Select retail or wholesale mode, search or scan a product and choose its selling unit and quantity.

Review prices, discounts, stock availability and the total. Choose the payment method and amount received. Unpaid credit requires a customer and must stay within the customer’s credit limit.

A below-cost sale needs the separate approval workflow and the correct permission. Cost Journey price and profit scenarios are estimates; they do not record a sale.

Complete checkout once and review the resulting invoice. The backend records the sale, batch allocations, stock movements, payment and audit history together. Use Invoices to reopen or print a sale.

## 6. Collect customer payments

Open a customer to review their invoice history, current debt, special unit prices and payment history. These current balances include later collections and returns.

Choose the unpaid invoice and record a payment with its method and reference. The amount cannot exceed that invoice’s outstanding balance. Check the updated balance before collecting again.

An old printed invoice may show the original checkout payment snapshot. Use the customer ledger or Customer Debt report for the updated balance.

## 7. Record damage, shortages and returns

Use Damage & missing to select the warehouse and batch, enter the quantity and a reason, and choose the correct action. Damaged goods are held separately from normal sellable stock.

Use Returns & refunds to select the original sale, return quantities and their disposition: sellable, damaged or discarded. Refunds need the required approval. Exchanges link the original return to a replacement sale.

Supplier returns preserve the original purchase currency and rate. Completed records are corrected with controlled returns, reversals or offsets; they are not permanently deleted.

## 8. Record expenses and understand profit

Record rent, salaries, utilities and similar business costs in Operating expenses. Choose the category, date, description, amount and payment details. Shipment-related transport and fees belong with the shipment.

Correct an expense using Reverse with a reason. The original entry remains in history, and the negative offset is recorded on the reversal date.

Gross profit is net sales after returns minus recorded landed cost of sold goods. Net profit also subtracts operating expenses. Collecting a customer debt does not create another sale.

Unavailable profit means costs are incomplete. Damage and shortage estimates are activity indicators and should not be added again as operating expenses.

## 9. Read Dashboard and Reports

Dashboard is the home page for accounts with dashboard access. It shows permitted sales, profit, debt, inventory value, stock warnings and recent activity. Use Refresh to request a new snapshot.

Reports contains 14 views: Sales, Purchase, Profit & Loss, Product Profitability, Transportation Cost, Shipment, Inventory, Stock Movement, Damage, Missing Product, Customer Debt, Supplier Payables, Expense and Currency Purchase.

Choose Today, This Week, This Month, This Year or Custom Date Range. For custom dates, choose both dates and press Apply dates. Dates use Myanmar time. Weeks start Monday, and the week/month/year presets end today.

Totals cover all matching records, not only the visible page. Use Next and Previous for more rows. Swipe or scroll wide tables horizontally to see all columns.

Inventory reconstructs opening and closing stock from movements. Debt reports show balances through the end date, including older unpaid invoices. Shipment status is its current state for shipments created in the selected period.

## 10. Missing pages, access and errors

Super Admin can access all business modules. Staff Admin sees only assigned tools. The Super Admin assigns permissions in Users & access; the Permissions page explains the available permissions.

Dashboard needs dashboard.view. Reports needs reports.view plus the underlying business permission. For example, Sales Report also needs sales.view; Purchase Report needs purchases.view and purchases.view_cost; Profit & Loss needs finance.view_profit.

If a page says Access restricted or No reports assigned, ask your Super Admin to check the relevant permissions. If no tools are assigned, the home page explains this and keeps the guide available.

If an expected page is missing even for Super Admin, the running app may be an older build. Reload the browser after the app has been updated. Updating source code alone does not rebuild a running Docker app.

If a form reports that stock, prices or a record changed, refresh the record and review the new values before submitting. After a connection error during a financial action, first check whether the invoice or payment was already saved; do not create another transaction blindly.

When reporting an error, include the page, action, message and time, and whether you are Super Admin or Staff Admin. Never share passwords or database credentials.
