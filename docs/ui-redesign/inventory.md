# Phase 1 — frontend surface inventory

Static inspection of every TSX page and component in the current workspace. Flags describe patterns to review, not automatic defects. Forms, dialogs and tables embedded in page files are included. API and mutation code stays unchanged.

78 files inventoried.

| Surface | Audit observations |
| --- | --- |
| `frontend/src/pages/Dashboard.tsx` | decorative gradient, local neutral palette, large radius |
| `frontend/src/pages/DesignSystem.tsx` | 10px text, native input, modal, drawer, shared table |
| `frontend/src/pages/Login.tsx` | decorative gradient, local neutral palette, large radius, 10px text, native input |
| `frontend/src/pages/Permissions.tsx` | native input, shared table |
| `frontend/src/pages/Users.tsx` | 10px text, native input, modal, drawer, shared table |
| `frontend/src/pages/Workspace.tsx` | 10px text |
| `frontend/src/pages/customers/Customers.tsx` | native input, modal, shared table |
| `frontend/src/pages/finance/AccountSelect.tsx` | Shared tokens / composition |
| `frontend/src/pages/finance/Accounts.tsx` | modal, shared table |
| `frontend/src/pages/finance/Creditors.tsx` | modal, shared table |
| `frontend/src/pages/finance/DeleteAccount.tsx` | modal |
| `frontend/src/pages/finance/Expenses.tsx` | native input, modal, shared table |
| `frontend/src/pages/finance/FundingSelect.tsx` | Shared tokens / composition |
| `frontend/src/pages/finance/Profit.tsx` | Shared tokens / composition |
| `frontend/src/pages/finance/SupplierFunding.tsx` | Shared tokens / composition |
| `frontend/src/pages/help/Home.tsx` | decorative gradient, local neutral palette, large radius |
| `frontend/src/pages/help/UserGuide.tsx` | Shared tokens / composition |
| `frontend/src/pages/insights/Assistant.tsx` | Shared tokens / composition |
| `frontend/src/pages/payments/Payments.tsx` | native input, modal, shared table |
| `frontend/src/pages/pos/Editors.tsx` | modal |
| `frontend/src/pages/pos/POS.tsx` | local neutral palette, large radius, 10px text, native input, modal |
| `frontend/src/pages/pos/PriceEditor.tsx` | bespoke table, modal |
| `frontend/src/pages/pos/Sales.tsx` | bespoke table, shared table |
| `frontend/src/pages/pos/WarehousePrices.tsx` | shared table |
| `frontend/src/pages/products/Catalog.tsx` | native input, modal, shared table |
| `frontend/src/pages/products/ProductForm.tsx` | native input |
| `frontend/src/pages/products/Products.tsx` | native input, shared table |
| `frontend/src/pages/purchases/CorrectionHistory.tsx` | Shared tokens / composition |
| `frontend/src/pages/purchases/CurrencySettings.tsx` | native input, shared table |
| `frontend/src/pages/purchases/PurchaseForm.tsx` | native input |
| `frontend/src/pages/purchases/PurchaseWorkflow.tsx` | large radius, bespoke table, native input, modal |
| `frontend/src/pages/purchases/Purchases.tsx` | shared table |
| `frontend/src/pages/purchases/SupplierBalance.tsx` | shared table |
| `frontend/src/pages/purchases/SupplierPayments.tsx` | native input, modal, shared table |
| `frontend/src/pages/receiving/Batches.tsx` | modal, shared table |
| `frontend/src/pages/receiving/Inventory.tsx` | modal, shared table |
| `frontend/src/pages/receiving/ManualStock.tsx` | modal |
| `frontend/src/pages/receiving/Receipts.tsx` | shared table |
| `frontend/src/pages/receiving/ReceiveForm.tsx` | native input |
| `frontend/src/pages/reports/ReportFilters.tsx` | Shared tokens / composition |
| `frontend/src/pages/reports/ReportResults.tsx` | shared table |
| `frontend/src/pages/reports/Reports.tsx` | Shared tokens / composition |
| `frontend/src/pages/returns/Returns.tsx` | native input, modal, shared table |
| `frontend/src/pages/returns/StockIssues.tsx` | native input, modal, shared table |
| `frontend/src/pages/shipments/CreateShipment.tsx` | native input, modal |
| `frontend/src/pages/shipments/Fields.tsx` | native input |
| `frontend/src/pages/shipments/LandedCost.tsx` | shared table |
| `frontend/src/pages/shipments/ShipmentActions.tsx` | Shared tokens / composition |
| `frontend/src/pages/shipments/Shipments.tsx` | modal, shared table |
| `frontend/src/pages/suppliers/SupplierForm.tsx` | native input |
| `frontend/src/pages/suppliers/Suppliers.tsx` | native input, shared table |
| `frontend/src/pages/transfers/Transfers.tsx` | native input, modal, shared table |
| `frontend/src/components/costs/cost-history.tsx` | Shared tokens / composition |
| `frontend/src/components/costs/cost-journey.tsx` | 10px text |
| `frontend/src/components/layout/app-shell.tsx` | local neutral palette, 10px text, drawer |
| `frontend/src/components/layout/header.tsx` | decorative gradient, local neutral palette, 10px text |
| `frontend/src/components/layout/sidebar.tsx` | decorative gradient, local neutral palette, 10px text |
| `frontend/src/components/shared/confirm-dialog.tsx` | local neutral palette, modal |
| `frontend/src/components/shared/currency-input.tsx` | Shared tokens / composition |
| `frontend/src/components/shared/data-table.tsx` | local neutral palette, bespoke table |
| `frontend/src/components/shared/decimal-input.tsx` | native input |
| `frontend/src/components/shared/drawer.tsx` | Shared tokens / composition |
| `frontend/src/components/shared/empty-state.tsx` | local neutral palette, large radius |
| `frontend/src/components/shared/filter-bar.tsx` | local neutral palette |
| `frontend/src/components/shared/form-field.tsx` | local neutral palette |
| `frontend/src/components/shared/fulfillment.tsx` | native input |
| `frontend/src/components/shared/loading-state.tsx` | local neutral palette |
| `frontend/src/components/shared/modal.tsx` | Shared tokens / composition |
| `frontend/src/components/shared/optional-section.tsx` | native input |
| `frontend/src/components/shared/overlay.tsx` | local neutral palette, large radius |
| `frontend/src/components/shared/page-header.tsx` | local neutral palette |
| `frontend/src/components/shared/permission-guard.tsx` | Shared tokens / composition |
| `frontend/src/components/shared/quantity-input.tsx` | Shared tokens / composition |
| `frontend/src/components/shared/search-input.tsx` | local neutral palette, native input |
| `frontend/src/components/shared/stat-card.tsx` | local neutral palette |
| `frontend/src/components/shared/status-badge.tsx` | local neutral palette |
| `frontend/src/components/ui/button.tsx` | local neutral palette |
| `frontend/src/components/ui/select.tsx` | local neutral palette |
