// Package permissions is the centralized vocabulary used by API route policies.
// PostgreSQL app.permissions is the authoritative grant catalog; never check role strings in handlers.
package permissions

type Code string

const (
	ProductsView          Code = "products.view"
	ProductsCreate        Code = "products.create"
	ProductsUpdate        Code = "products.update"
	PurchasesView         Code = "purchases.view"
	PurchasesCreate       Code = "purchases.create"
	PurchasesViewCost     Code = "purchases.view_cost"
	InventoryView         Code = "inventory.view"
	InventoryAdjust       Code = "inventory.adjust"
	SalesCreate           Code = "sales.create"
	SalesDiscount         Code = "sales.discount"
	FinanceViewProfit     Code = "finance.view_profit"
	FinanceViewLandedCost Code = "finance.view_landed_cost"
	ReportsView           Code = "reports.view"
	UsersManage           Code = "users.manage"
	SettingsManage        Code = "settings.manage"
	PermissionsManage     Code = "permissions.manage"
	SuperAdmin                 = "SUPER_ADMIN"
	StaffAdmin                 = "STAFF_ADMIN"
)
