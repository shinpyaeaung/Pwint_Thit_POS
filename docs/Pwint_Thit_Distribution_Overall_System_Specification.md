# Pwint Thit Distribution
## Custom POS/PVS Distribution Management System

## 1. System Overview

The proposed system is the **Pwint Thit Distribution production-level, web-based Custom POS/PVS and Distribution Management System**, designed specifically for a retail and wholesale product distribution business.

The business mainly distributes **Indian products**, with the possibility of expanding in the future to products from **Thailand, China, and other countries**.

The main product categories include:

- Food and beverages
- Cosmetics
- Consumer goods
- Household products
- Other retail and wholesale products

Unlike a normal POS system that mainly focuses on selling products, this system should manage the complete product lifecycle:

**Supplier Purchase → Transportation → Receiving → Inventory → Cost Calculation → Pricing → Sales → Damage/Loss → Profit/Loss**

The most important purpose of the system is to accurately determine the **real cost of every product** before it is sold.

---

## 2. Main Business Concept

The business does not normally purchase products directly from manufacturers.

Products are usually purchased from:

- Suppliers
- Distributors
- Importers
- Other wholesalers

After purchasing, the products may need to travel through several cities or transportation providers before reaching the final warehouse or shop.

Therefore, the original supplier price alone cannot be considered the real product cost.

The system should calculate:

**Purchase Cost**

+

**Transportation Cost**

+

**Other Related Costs**

=

**Actual Product Cost / Landed Cost**

The Actual Product Cost should then be used to calculate selling prices, profit, and loss.

---

## 3. Product Management

The system should maintain a central product database.

Each product may contain:

- Product name
- SKU/Product Code
- Barcode
- Brand
- Category
- Country of origin
- Product image
- Description
- Supplier
- Purchase unit
- Selling unit
- Units per carton
- Retail price
- Wholesale price
- Current stock
- Minimum stock level
- Batch number
- Expiry date, if applicable
- Product status

Examples of product units include:

- Piece
- Bottle
- Pack
- Packet
- Bundle
- Box
- Bag
- Carton
- Case
- Card

The system should support different packaging structures.

For example:

**1 Carton = 12 Bottles**

or:

**1 Carton = 24 Packs**

This is important because products may be purchased by carton but sold individually.

---

## 4. Supplier Management

The system should maintain supplier information.

Supplier records may contain:

- Supplier name
- Contact person
- Phone number
- Address
- Country
- Supplier type
- Products supplied
- Payment terms
- Outstanding balance
- Purchase history
- Notes

The business should be able to view all previous purchases from a particular supplier.

---

## 5. Purchasing Management

When products are purchased, a purchase record should be created.

For example:

**Product 1**

**1 Carton = 12 Bottles**

**12 × 10,000 = 120,000**

Where:

- **12** = quantity inside the carton
- **10,000** = purchase price per bottle
- **120,000** = total purchase cost

The system should record:

- Supplier
- Purchase date
- Product
- Quantity
- Carton quantity
- Unit quantity
- Unit purchase price
- Carton purchase price
- Total purchase amount
- Purchase invoice number
- Payment status
- Amount paid
- Outstanding amount
- Notes

However, this purchase amount is only the original purchase cost.

Transportation and other costs must still be added.

---

## 6. Shipment Management

Each purchase or group of purchases may be connected to a **shipment**.

A shipment represents the movement of products from the supplier to the final business location.

A shipment record should contain:

- Shipment number
- Supplier
- Products included
- Starting location
- Final destination
- Shipment date
- Expected arrival
- Actual arrival
- Current shipment status
- Transportation stages
- Total transportation cost
- Additional expenses
- Notes

Possible shipment statuses include:

- Preparing
- In Transit
- Arrived
- Received
- Cancelled

---

## 7. Multi-Stage Transportation Management

This is one of the most important parts of the system.

Products are not always transported directly from one city to another.

For example:

**City A → City B → City C**

Transportation costs may be:

**City A → City B = 30,000**

**City B → City C = 50,000**

The total transportation cost is:

**30,000 + 50,000 = 80,000**

There may also be additional transportation stages:

**City A → City B → City D → City C**

The system must allow users to add as many transportation stages as necessary.

Each stage should contain:

- Starting location
- Destination
- Transportation provider
- Transportation type
- Vehicle information if needed
- Departure date
- Arrival date
- Transportation fee
- Loading fee
- Unloading fee
- Other charges
- Payment status
- Notes

The system should automatically calculate the total transportation cost of the shipment.

---

## 8. Additional Shipment Expenses

Transportation may not be the only additional cost.

Other shipment-related expenses may include:

- Loading fees
- Unloading fees
- Handling fees
- Warehouse fees
- Packaging fees
- Transfer fees
- Customs charges
- Taxes
- Service fees
- Labour fees
- Other miscellaneous expenses

All these expenses should be connected to the related shipment.

---

## 9. Actual Product Cost / Landed Cost

The system should calculate the actual cost of the shipment.

Example:

**Purchase Cost = 120,000**

**Transportation Stage 1 = 30,000**

**Transportation Stage 2 = 50,000**

Therefore:

**Total Transportation Cost = 80,000**

and:

**Actual Total Cost = 120,000 + 80,000**

**Actual Total Cost = 200,000**

The system should use **200,000** as the real cost instead of the original 120,000 purchase price.

The main formula is:

**Actual Product Cost = Purchase Cost + Transportation Cost + Other Related Expenses**

---

## 10. Cost Allocation

This is an important feature that should be included.

A single shipment may contain several different products.

For example:

- Product A
- Product B
- Product C

If transportation cost is **300,000**, the system needs a method to distribute this cost across the products.

Transportation costs may be allocated based on:

- Product quantity
- Purchase value
- Weight
- Carton quantity
- Manual allocation

The system should allow the business to choose the most appropriate allocation method.

This makes the actual cost calculation much more accurate.

---

## 11. Actual Unit Cost

After calculating the landed cost, the system should calculate the actual cost per individual item.

Example:

**Actual Carton Cost = 200,000**

**Quantity = 12 Bottles**

Therefore:

**200,000 ÷ 12 = 16,666.67 per Bottle**

Although the original supplier price was:

**10,000 per Bottle**

the real cost becomes:

**16,666.67 per Bottle**

after transportation and related expenses.

---

## 12. Goods Receiving

When the shipment arrives, warehouse staff should record the received goods.

The system should compare:

**Expected Quantity vs Received Quantity**

For example:

Expected:

**12 Cartons**

Received:

**11 Cartons + 8 Bottles**

If quantities do not match, the system should record the difference.

Receiving records should include:

- Shipment
- Product
- Expected quantity
- Received quantity
- Missing quantity
- Damaged quantity
- Date received
- Received by
- Notes

---

## 13. Inventory Management

After receiving the goods, stock should be updated automatically.

Inventory should support:

- Carton stock
- Individual unit stock
- Available stock
- Damaged stock
- Reserved stock
- Stock movements
- Stock adjustments

For example:

**1 Carton = 12 Bottles**

If one carton is opened and three bottles are sold:

**Remaining Stock = 9 Bottles**

The system should correctly maintain the quantity.

---

## 14. Batch and Expiry Management

For food, beverages, cosmetics, and other products with expiry dates, the system should support batch management.

Each batch may include:

- Batch number
- Product
- Purchase date
- Received date
- Manufacturing date
- Expiry date
- Quantity
- Supplier
- Actual cost

The system should provide warnings for products that are close to expiry.

---

## 15. Selling Price Management

Selling prices may be set manually or calculated based on profit.

For example:

**Actual Carton Cost = 200,000**

Selling Price:

**210,000**

Profit:

**210,000 - 200,000 = 10,000**

The system should support:

- Retail price
- Wholesale price
- Unit price
- Carton price
- Promotional price
- Special customer price
- Negotiated price

---

## 16. Percentage-Based Profit

The business may also set selling prices using a profit percentage.

For example:

**Actual Cost = 200,000**

If the business wants a **10% markup**:

**Profit = 20,000**

**Selling Price = 220,000**

The system should automatically calculate the suggested selling price.

---

## 17. Minimum Selling Price Protection

The system should clearly show the actual cost when a user changes the selling price.

For example:

**Actual Unit Cost = 16,666.67**

User enters:

**Selling Price = 15,000**

The system should display a warning such as:

> **This sale is below the actual product cost and will result in a loss.**

Normal sales staff may be prevented from completing such a sale.

A manager or owner may be allowed to approve it.

---

## 18. Retail and Wholesale POS

The actual sales process should work similarly to a standard POS system.

Staff should be able to:

- Search products
- Scan barcodes
- Add products to cart
- Change quantity
- Sell individual units
- Sell cartons
- Select retail or wholesale pricing
- Apply approved discounts
- Select customer
- Calculate totals
- Receive payment
- Print or generate invoice
- Complete the sale

Inventory should automatically decrease after the sale.

---

## 19. Customer Management

The system should maintain customer information, especially for wholesale customers.

Customer information may include:

- Customer name
- Business name
- Phone number
- Address
- Customer type
- Retail/Wholesale status
- Purchase history
- Special pricing
- Credit balance
- Outstanding balance
- Notes

---

## 20. Credit Sales and Customer Debt

This is recommended because wholesale customers may not always pay immediately.

For example:

**Invoice Total = 500,000**

**Customer Pays = 300,000**

**Remaining = 200,000**

The system should record:

- Total invoice
- Amount paid
- Remaining amount
- Due date
- Payment history
- Outstanding balance

Customer payment statuses may include:

- Paid
- Partially Paid
- Unpaid
- Overdue

---

## 21. Supplier Payables

The same concept should apply when the business purchases from suppliers on credit.

For example:

**Purchase Total = 1,000,000**

**Paid = 600,000**

**Supplier Balance = 400,000**

The system should track how much the business still owes each supplier.

---

## 22. Damaged Products

Products may be damaged during transportation, storage, or handling.

For example:

**1 Carton = 12 Bottles**

If one bottle is damaged:

**Normal Sellable Quantity = 11 Bottles**

The system should record:

- Product
- Batch
- Damaged quantity
- Date
- Reason
- Related shipment
- Responsible location
- Estimated loss
- Notes

Damaged products should not remain part of normal available stock.

---

## 23. Missing Products

Products may also be missing.

For example:

**Expected = 100 Bottles**

**Received = 98 Bottles**

**Missing = 2 Bottles**

The system should record the missing quantity and calculate the financial effect.

---

## 24. Reduced-Price Damaged Goods

Sometimes a damaged product may still be sellable.

For example, the outer packaging may be damaged but the product itself is still usable.

The business may choose to sell it at a reduced price.

The system should store:

- Original selling price
- Reduced selling price
- Product cost
- Loss from discount
- Reason

---

## 25. Sales Returns

Customers may return products.

The system should support:

- Full return
- Partial return
- Exchange
- Refund
- Damaged return

When a valid return happens, stock and financial records should be adjusted correctly.

---

## 26. Purchase Returns

Sometimes products may need to be returned to the supplier.

The system should record:

- Supplier
- Product
- Quantity returned
- Reason
- Return date
- Refund or supplier credit
- Notes

---

## 27. Profit and Loss Management

Profit and loss is one of the most important parts of the system.

The basic calculation is:

**Gross Profit = Selling Price - Actual Product Cost**

Example:

**Actual Cost = 200,000**

**Selling Price = 210,000**

Therefore:

**Gross Profit = 10,000**

If the selling price is below the actual cost, the system records a loss.

---

## 28. Business-Level Profit

Product profit alone is not enough to determine the real business profit.

The system should also consider operating expenses.

For example:

**Sales Revenue**

− **Cost of Goods Sold**

= **Gross Profit**

Then:

**Gross Profit**

− **Business Operating Expenses**

= **Net Profit**

Operating expenses may include:

- Rent
- Salaries
- Electricity
- Internet
- Marketing
- Fuel
- Maintenance
- Office expenses
- Warehouse expenses
- Other operating expenses

---

## 29. Expense Management

The system should allow users to record business expenses separately.

Each expense should include:

- Expense category
- Amount
- Date
- Description
- Payment method
- Recorded by
- Receipt or attachment
- Notes

This allows more accurate Profit and Loss reporting.

---

## 30. Cash and Payment Management

The system should support multiple payment methods.

Examples:

- Cash
- Bank transfer
- Mobile payment
- Credit
- Partial payment
- Other payment methods

For each payment, the system should record:

- Amount
- Payment method
- Date
- Reference number
- Related transaction

---

## 31. Multi-Currency and Exchange Rate Management

Multi-currency support is a **core requirement** because Pwint Thit Distribution may purchase products using foreign currencies, especially Indian Rupee.

The main/base currency of the system is:

- **MMK – Myanmar Kyat**

Supported purchase currencies may include:

- INR – Indian Rupee
- THB – Thai Baht
- CNY – Chinese Yuan
- USD – US Dollar
- Other currencies when required

Every foreign-currency purchase should store:

- Original foreign-currency amount
- Currency code
- Exchange rate used for the transaction
- Converted MMK amount
- Transaction date

Example:

**Supplier Price = 10,000 INR**

If:

**1 INR = 25 MMK**

Then:

**Purchase Cost in MMK = 10,000 × 25 = 250,000 MMK**

The converted MMK value must be used in landed-cost, inventory-cost, profit, and reporting calculations.

Historical exchange rates must be preserved. If the exchange rate changes later, completed purchases must not be recalculated automatically.

---

## 32. Warehouse Management

If the business has more than one warehouse or shop in the future, the system should support multiple locations.

For example:

- Main Warehouse
- Shop 1
- Shop 2
- Branch Warehouse

The system should track inventory separately for each location.

---

## 33. Stock Transfer

Products may need to be moved between warehouses or shops.

For example:

**Main Warehouse → Shop 1**

The system should record:

- From location
- To location
- Product
- Quantity
- Transfer date
- Status
- Staff
- Notes

---

## 34. Stock Adjustment

Sometimes physical stock may not match the system quantity.

The system should support stock adjustments.

Reasons may include:

- Counting error
- Damaged item
- Lost product
- Expired product
- Manual correction

Every adjustment should be recorded for auditing.

---

## 35. Stock Taking

The system should support physical inventory counting.

Staff can compare:

**System Quantity**

vs.

**Physical Quantity**

Any difference should be recorded and approved.

---

## 36. Low-Stock Alerts

Each product should have an optional minimum stock level.

For example:

**Minimum Stock = 20 Bottles**

If stock reaches 18 bottles, the system should display a low-stock warning.

This helps the business know when products need to be reordered.

---

## 37. Expiry Alerts

For applicable products, the system should show products that will expire soon.

Examples:

- Expiring within 30 days
- Expiring within 60 days
- Already expired

Expired products should not be sold normally.

---

## 38. Dashboard

The dashboard should provide a quick overview of the business.

Important information may include:

- Today's sales
- Today's profit
- Monthly sales
- Monthly profit
- Total purchases
- Total transportation cost
- Total expenses
- Outstanding customer debt
- Outstanding supplier debt
- Inventory value
- Low-stock products
- Expiring products
- Damaged products
- Top-selling products
- Most profitable products
- Recent transactions

---

## 39. Reports

The system should provide reports such as:

- Sales Report
- Purchase Report
- Profit and Loss Report
- Product Profitability Report
- Transportation Cost Report
- Shipment Report
- Supplier Report
- Customer Report
- Retail Sales Report
- Wholesale Sales Report
- Inventory Report
- Stock Movement Report
- Damaged Product Report
- Missing Product Report
- Expiry Report
- Expense Report
- Customer Debt Report
- Supplier Payable Report
- Payment Report

Reports should support date filtering.

For example:

- Today
- This week
- This month
- This year
- Custom date range

---

## 40. User Roles

The system will use **only two user roles**:

### Super Admin

The Super Admin has full control of the system, including:

- Products
- Suppliers
- Purchases
- Purchase costs
- Foreign-currency values and exchange rates
- Actual landed costs
- Shipments and transportation
- Goods receiving
- Inventory
- POS and sales
- Customers
- Payments
- Expenses
- Profit and loss
- Reports
- Staff Admin accounts
- Permission management
- Approvals
- Audit logs
- System settings

### Staff Admin

Staff Admin users handle daily business operations. Their access must be controlled by configurable permissions set by the Super Admin.

Depending on permission, a Staff Admin may access:

- Dashboard
- POS
- Sales
- Products
- Customers
- Payments
- Purchases
- Shipments
- Transportation
- Goods receiving
- Inventory
- Stock taking
- Damaged / missing products
- Expenses
- Selected reports

Sensitive financial or administrative functions may be hidden or blocked unless explicitly granted.

---

## 41. Role-Based Permissions

Permissions must be configurable for each Staff Admin account.

The Super Admin always has full access.

A Staff Admin may be granted permissions such as:

- Use POS
- Create sales
- View products
- Create or update products
- Manage customers
- Record payments
- View inventory
- Receive goods
- Record damaged or missing products
- View shipments
- Update shipment status
- Record transportation expenses
- Record business expenses
- Process returns
- View selected reports
- Perform stock taking

Sensitive permissions should normally be restricted unless the Super Admin explicitly allows them. Examples include:

- View supplier purchase cost
- View landed cost
- View gross profit or net profit
- Change exchange rates
- Change purchase costs
- Change transportation costs
- Sell below actual cost
- Apply large discounts
- Approve refunds
- Void or reverse transactions
- Approve stock adjustments
- View audit logs

The frontend should hide restricted actions, but the **Go backend must also validate permissions for every protected API action**. Frontend hiding alone is not sufficient security.

---

## 42. Approval System

Important actions should require approval.

Examples include:

- Selling below actual cost
- Large discounts
- Deleting transactions
- Changing purchase costs
- Changing transportation costs
- Stock adjustments
- Refunds

The Super Admin can approve these actions, or explicitly grant the required permission to a Staff Admin where appropriate.

---

## 43. Audit Logs

Every important system action should be recorded.

The system should track:

- User
- Action
- Date and time
- Old value
- New value
- Related record

For example:

**User A changed Product X wholesale price from 20,000 to 18,500.**

This helps prevent fraud and accidental changes.

---

## 44. Document Attachments

The system should allow documents or images to be attached to relevant records.

Examples:

- Supplier invoice
- Purchase receipt
- Transportation receipt
- Payment slip
- Product photo
- Damage photo

This can help verify transactions later.

---

## 45. Notifications and Alerts

The system may provide notifications for:

- Low stock
- Product expiry
- Customer overdue payments
- Supplier payments due
- Shipment arrival
- Damaged products
- Large losses
- Sale below cost
- Pending approvals

---

## 46. Data Backup and Recovery

Because the system contains important financial and inventory information, regular backups are necessary.

The production system should include:

- Automated database backups
- Secure backup storage
- Restore procedures
- Protection against accidental deletion

---

## 47. Security

The production system should include:

- Secure user login
- Role-based access control
- Strong password policies
- Session management
- Audit logging
- Secure database access
- HTTPS
- Input validation
- Protection against common web attacks
- Backup and recovery

Sensitive information such as purchase costs and profit reports should only be available to authorized users.

---

## 48. Main System Modules

The final system can be organised into the following major modules:

1. **Dashboard**
2. **Products**
3. **Categories**
4. **Brands**
5. **Suppliers**
6. **Purchases**
7. **Shipments**
8. **Transportation**
9. **Goods Receiving**
10. **Inventory**
11. **Warehouses**
12. **Stock Transfers**
13. **Stock Adjustments**
14. **Damaged / Missing Products**
15. **POS**
16. **Sales**
17. **Customers**
18. **Retail / Wholesale Pricing**
19. **Customer Credit**
20. **Supplier Payables**
21. **Payments**
22. **Sales Returns**
23. **Purchase Returns**
24. **Expenses**
25. **Profit & Loss**
26. **Reports**
27. **Users & Roles**
28. **Approvals**
29. **Audit Logs**
30. **Settings**

---

## 49. Complete Business Flow

The complete business workflow can be:

**Create / Select Supplier**

↓

**Purchase Products**

↓

**Record Original Purchase Cost**

↓

**Create Shipment**

↓

**Add Products to Shipment**

↓

**Transportation Stage 1**

↓

**Transportation Stage 2**

↓

**Additional Transportation Stages**

↓

**Add Other Shipment Expenses**

↓

**Calculate Total Shipment Cost**

↓

**Allocate Shipment Costs to Products**

↓

**Calculate Actual/Landed Product Cost**

↓

**Receive Goods**

↓

**Record Damaged or Missing Quantities**

↓

**Update Inventory**

↓

**Calculate Actual Cost Per Unit**

↓

**Set Retail and Wholesale Prices**

↓

**Sell Through POS**

↓

**Receive Customer Payment**

↓

**Record Returns / Damage / Adjustments**

↓

**Calculate Product Profit**

↓

**Subtract Operating Expenses**

↓

**Calculate Final Business Profit or Loss**

↓

**Generate Reports**

---

## 50. Core Financial Logic

The core financial calculation should be:

**Original Purchase Cost**

+

**Transportation Cost**

+

**Shipment Expenses**

=

**Landed Cost / Actual Product Cost**

Then:

**Actual Product Cost ÷ Sellable Quantity**

=

**Actual Cost Per Unit**

Then:

**Selling Price − Actual Cost**

=

**Gross Profit**

At the overall business level:

**Total Sales Revenue**

−

**Cost of Goods Sold**

=

**Gross Profit**

Then:

**Gross Profit − Operating Expenses**

=

**Net Profit / Loss**

---

## 51. Important Recommendation: Preserve Historical Costs

One important rule is that historical product costs should not be overwritten.

For example, Product A may arrive in January with:

**Actual Cost = 15,000**

The same product may arrive again in March with:

**Actual Cost = 18,000**

The system should preserve both purchase batches instead of replacing the old cost with the new one.

This is important for accurate profit reporting.

---

## 52. Important Recommendation: Batch-Based Costing

Each shipment or purchase batch should keep its own actual cost.

For example:

**Batch A**

100 Bottles

Actual Cost = 15,000 each

**Batch B**

100 Bottles

Actual Cost = 18,000 each

The system can then use an inventory costing method such as **FIFO** or another selected method when calculating cost of goods sold.

For this type of business, FIFO is usually a practical starting approach, especially for products that have expiry dates.

---

## 53. Important Recommendation: Separate Gross Profit and Net Profit

The system should not treat:

**Selling Price − Purchase Price**

as the final business profit.

Instead, it should separate:

### Gross Profit

Revenue minus the actual cost of sold products.

### Net Profit

Gross profit minus operating expenses.

This provides a more accurate understanding of business performance.

---

## 54. Important Recommendation: Keep Transportation as a Separate Module

Transportation should not simply be entered as one number inside a purchase record.

It should have its own module because transportation may involve:

- Multiple stages
- Multiple providers
- Multiple payments
- Multiple cities
- Different fees
- Different dates
- Additional charges

This will make the system easier to maintain and more accurate.

---

## 55. Important Recommendation: Do Not Delete Important Transactions

In a production system, completed sales, purchases, payments, and stock movements should normally not be permanently deleted.

Instead, the system should use statuses such as:

- Cancelled
- Voided
- Reversed

The original record should remain available in the audit history.

This protects financial data and makes auditing easier.

---

## 56. Final System Objective

The main purpose of the Pwint Thit Distribution Custom POS/PVS Distribution Management System is to give the business full control over the complete movement and financial value of its products.

The system should answer important questions such as:

- How much did we originally pay for this product?
- How much did transportation cost?
- How much did this shipment actually cost us?
- What is the real cost per bottle, pack, carton, or piece?
- How much stock do we currently have?
- How much stock was damaged or lost?
- What price are we selling at?
- Are we selling above or below cost?
- How much profit did we make from this product?
- How much profit did we make from this shipment?
- How much does each customer owe us?
- How much do we owe suppliers?
- What are our total business expenses?
- What is our actual net profit or loss?

The core concept of the entire system is:

**Purchase**

→ **Transport**

→ **Calculate Real Cost**

→ **Receive Inventory**

→ **Set Price**

→ **Sell**

→ **Track Payments and Stock**

→ **Handle Damage / Returns / Loss**

→ **Calculate Profit & Loss**

→ **Generate Reports**

This makes the system more than a normal POS. It becomes a complete **Distribution, Multi-Currency Costing, Inventory, Sales, and Financial Management System** for **Pwint Thit Distribution**.

---

# 57. Recommended Technology Stack

The system should use a compact, fast, modern, and maintainable web architecture.

## Frontend

- **React**
- **Vite**
- **TypeScript**
- **Tailwind CSS**
- **shadcn/ui**
- **Framer Motion**
- **TanStack Query**
- **Zustand**

## Backend

- **Go**
- **Gin**

## Database Layer

- **PostgreSQL**
- **pgx**
- **sqlc**

## Optional Infrastructure

- **Redis** only when caching, queues, distributed sessions, or higher load actually requires it

## Deployment

- **Docker**
- **Nginx or Caddy**
- **Linux VPS**

## File Storage

Use local or S3-compatible object storage for product images, invoices, receipts, payment slips, and damage photos.

Recommended architecture:

```text
React + Vite + TypeScript
          ↓
       Go + Gin
          ↓
      pgx + sqlc
          ↓
      PostgreSQL
```

The frontend should never connect directly to PostgreSQL. All protected business operations should go through the Go backend.

---

# 58. PostgreSQL Transaction Rules

Important business operations should use PostgreSQL transactions.

Example sale flow:

```text
Create Sale
    ↓
Create Sale Items
    ↓
Deduct Inventory
    ↓
Record Payment
    ↓
Create Inventory Movement
    ↓
Create Audit Log
    ↓
COMMIT
```

If an important step fails, the transaction should use:

```text
ROLLBACK
```

This prevents incomplete sales or incorrect stock balances.

---

# 59. Recommended Database Areas

Main tables may include:

- users
- roles
- permissions
- user_permissions
- products
- categories
- brands
- suppliers
- purchases
- purchase_items
- currencies
- exchange_rates
- shipments
- shipment_items
- transportation_stages
- shipment_expenses
- goods_receiving
- batches
- inventory
- inventory_movements
- stock_adjustments
- customers
- sales
- sale_items
- payments
- expenses
- customer_debts
- supplier_payables
- sales_returns
- purchase_returns
- damaged_products
- missing_products
- approvals
- audit_logs
- attachments

The roles table should contain only:

- `SUPER_ADMIN`
- `STAFF_ADMIN`

Fine-grained permissions should control what each Staff Admin is allowed to do.

---

# 60. Frontend UI Direction

The frontend should feel:

- Modern
- Compact
- Fast
- Unique
- Professional
- Easy to scan
- Suitable for daily retail and wholesale operations

The UI should not look like a generic copied admin dashboard.

The design identity should come from Pwint Thit branding and distribution-focused workflows.

## Main Brand Colors

### Primary Red

**#ba0d0d**

Use for:

- Main actions
- Primary buttons
- Active navigation
- Selected tabs
- POS checkout
- Branding
- Important totals

### Accent Yellow

**#f7a712**

Use for:

- Warnings
- Low-stock indicators
- Pending status
- Highlights
- Secondary emphasis

### Supporting Neutral Colors

- Background: `#f8f8f8`
- Cards: `#ffffff`
- Primary text: `#171717`
- Secondary text: `#737373`
- Borders: `#e5e5e5`

Red and yellow should be used intentionally rather than covering the whole interface.

---

# 61. UI Layout

Recommended layout:

```text
┌──────────────────────────────────────────────────────────────┐
│ Pwint Thit      Global Search         Alerts      Profile   │
├──────────────┬───────────────────────────────────────────────┤
│              │                                               │
│ Dashboard    │  Main Page Content                            │
│ POS          │                                               │
│ Sales        │                                               │
│ Products     │                                               │
│ Inventory    │                                               │
│ Purchases    │                                               │
│ Shipments    │                                               │
│ Suppliers    │                                               │
│ Customers    │                                               │
│ Expenses     │                                               │
│ Reports      │                                               │
│ Settings     │                                               │
└──────────────┴───────────────────────────────────────────────┘
```

Recommended sidebar groups:

```text
PWINT THIT
DISTRIBUTION

OVERVIEW
- Dashboard

SALES
- POS
- Sales
- Customers
- Payments

PRODUCT & STOCK
- Products
- Inventory
- Stock Taking
- Damage / Missing

PURCHASING
- Suppliers
- Purchases
- Shipments
- Transportation
- Receiving

FINANCE
- Expenses
- Customer Credit
- Supplier Payables
- Profit & Loss

INSIGHTS
- Reports

SYSTEM
- Users
- Permissions
- Audit Logs
- Settings
```

Menu items must automatically be hidden when a Staff Admin does not have the required permission.

---

# 62. Unique Pwint Thit Cost Journey Component

A signature UI component should show how the real cost was formed.

Example:

```text
Product: Get Real Shampoo

Original Purchase
10,000 INR
    ↓
Exchange Rate
1 INR = 25 MMK
    ↓
Converted Purchase
250,000 MMK
    ↓
Transportation
40,000 MMK
    ↓
Other Expenses
10,000 MMK
    ↓
----------------
Landed Cost
300,000 MMK
    ↓
Selling Price
340,000 MMK
    ↓
Profit
+40,000 MMK
```

This should become one of the unique visual features of the Pwint Thit system.

---

# 63. Framer Motion Guidelines

Use Framer Motion for subtle and professional interactions such as:

- Page transitions
- Sidebar active indicator
- Card hover motion
- Modal enter / exit
- Drawer animation
- Table row appearance
- Number transitions
- Expand / collapse sections
- Toast notifications

Avoid excessive bouncing, spinning, or decorative animation that slows down POS work.

Example:

```tsx
<motion.div
  initial={{ opacity: 0, y: 8 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.2 }}
>
  {children}
</motion.div>
```

---

# 64. UI Component Style

Recommended design rules:

- Border radius: 12–16px
- Button radius: 10–12px
- Soft borders
- Very light shadows
- Compact spacing
- High information density
- Clear typography
- Strong financial-number hierarchy
- Consistent icon style
- Responsive tables
- Sticky table headers where useful

Recommended fonts:

- **Inter**
- **Geist**

Use tabular numbers for financial values:

```css
font-variant-numeric: tabular-nums;
```

---

# 65. Frontend State and API Handling

## TanStack Query

Use for server data such as:

- Products
- Sales
- Inventory
- Purchases
- Customers
- Dashboard data
- Reports
- Shipments
- Payments

It should handle fetching, loading states, caching, refetching, mutations, and stale-data invalidation.

## Zustand

Use only for small frontend state such as:

- Sidebar state
- Current POS cart
- Temporary filters
- Modal state
- UI preferences

Important business data should remain on the server.

---

# 66. Recommended Frontend Structure

```text
src/
├── components/
│   ├── ui/
│   ├── layout/
│   ├── dashboard/
│   ├── pos/
│   ├── products/
│   ├── inventory/
│   ├── purchases/
│   ├── shipments/
│   └── shared/
├── pages/
│   ├── dashboard/
│   ├── pos/
│   ├── sales/
│   ├── products/
│   ├── inventory/
│   ├── suppliers/
│   ├── purchases/
│   ├── shipments/
│   ├── customers/
│   ├── expenses/
│   ├── reports/
│   └── settings/
├── hooks/
├── stores/
├── services/
├── types/
├── permissions/
└── lib/
```

---

# 67. MoSCoW Prioritization

The project uses three active priority groups:

- **Must Have**
- **Should Have**
- **Could Have**

## Must Have

- Product Management
- Supplier Management
- Purchasing
- Multi-Currency Support
- INR to MMK and other currency conversion
- Historical exchange-rate storage
- Shipment Management
- Multi-Stage Transportation
- Shipment Expense Management
- Landed-Cost Calculation
- Cost Allocation
- Actual Unit Cost
- Goods Receiving
- Inventory Management
- Retail and Wholesale Pricing
- Minimum Selling Price Protection
- POS
- Customer Management
- Payment Management
- Damage / Missing Product Management
- Profit and Loss Calculation
- Basic Reports
- Authentication
- Super Admin Role
- Staff Admin Role
- Permission Management
- Backend Authorization

## Should Have

- Batch Management
- Expiry Management
- Customer Credit
- Customer Debt
- Supplier Payables
- Sales Returns
- Purchase Returns
- Expense Management
- Stock Adjustment
- Stock Taking
- Low-Stock Alerts
- Expiry Alerts
- Approval System
- Audit Logs
- Dashboard
- Backup and Recovery

## Could Have

- Multiple Warehouses
- Multiple Shops
- Stock Transfers
- Promotional Pricing
- Special Customer Pricing
- Negotiated Pricing
- Document Attachments
- Product Images
- Advanced Notifications
- Advanced Analytics
- Currency Purchase Analysis
- Supplier Performance Reports
- Customer Purchase Trends
- Profit by Shipment
- Profit by Batch

---

# 68. Recommended Development Phases

## Phase 1 – Foundation

- Authentication
- Super Admin
- Staff Admin
- Permission system
- Product management
- Supplier management
- PostgreSQL schema
- Main layout and design system

## Phase 2 – Purchasing and Costing

- Purchases
- Multi-currency
- Exchange rates
- Shipments
- Transportation
- Shipment expenses
- Cost allocation
- Landed cost
- Actual unit cost

## Phase 3 – Inventory

- Goods receiving
- Inventory
- Batch management
- Damage / missing goods
- Stock adjustment
- Stock taking

## Phase 4 – Sales

- POS
- Retail pricing
- Wholesale pricing
- Customers
- Payments
- Credit sales
- Returns

## Phase 5 – Finance and Control

- Supplier payables
- Expenses
- Profit and loss
- Approval workflow
- Audit logs
- Reports

## Phase 6 – Improvement

- Advanced dashboard
- Alerts
- Multiple warehouses
- Advanced analytics
- Attachments
- Performance optimization

---

# 69. Final Recommended Identity

The unique value of the Pwint Thit system should come from its real business workflow rather than from using unnecessarily unusual technologies.

Its strongest features are:

- Foreign currency / INR to MMK costing
- Historical exchange-rate preservation
- Multi-stage transportation
- Transportation-cost allocation
- Landed-cost calculation
- Carton-to-unit inventory handling
- Retail and wholesale pricing
- Below-cost sale protection
- Damaged and missing stock management
- Customer credit
- Supplier payables
- Profit and loss tracking
- Fine-grained Staff Admin permissions
- Auditability
- Cost Journey visualization

The final product is a complete:

**Distribution + Multi-Currency Costing + Inventory + POS + Sales + Financial Management System**

for **Pwint Thit Distribution**.

