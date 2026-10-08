package reports

import "github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/permissions"

var policies = map[string][]permissions.Code{
	"payments":              {permissions.PaymentsManage, permissions.PurchasesViewCost, permissions.ShipmentsViewCost, permissions.CustomersManage, permissions.ExpensesManage},
	"sales":                 {permissions.SalesView},
	"purchases":             {permissions.PurchasesView, permissions.PurchasesViewCost},
	"profit-loss":           {permissions.FinanceViewProfit},
	"product-profitability": {permissions.FinanceViewProfit},
	"transportation":        {permissions.ShipmentsView, permissions.ShipmentsViewCost},
	"shipments":             {permissions.ShipmentsView},
	"inventory":             {permissions.InventoryView},
	"stock-movements":       {permissions.InventoryView},
	"damage":                {permissions.DamageManage, permissions.FinanceViewLandedCost},
	"missing":               {permissions.DamageManage, permissions.FinanceViewLandedCost},
	"customer-debt":         {permissions.CustomersManage},
	"supplier-payables":     {permissions.PurchasesView, permissions.PurchasesViewCost},
	"expenses":              {permissions.ExpensesManage},
	"currency-purchases":    {permissions.PurchasesView, permissions.PurchasesViewCost},
}
