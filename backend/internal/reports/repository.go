package reports

import (
	"context"
	"fmt"
	"github.com/shinpyaeaung/Pwint_Thit_POS/backend/internal/database"
)

type SQLRepository struct{ queries *database.Queries }

func NewRepository(db database.DBTX) *SQLRepository { return &SQLRepository{queries: database.New(db)} }
func (r *SQLRepository) Read(ctx context.Context, id string, f Filter) ([]byte, error) {
	switch id {
	case "sales":
		return r.queries.ReportSales(ctx, database.ReportSalesParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "purchases":
		return r.queries.ReportPurchases(ctx, database.ReportPurchasesParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "profit-loss":
		return r.queries.ReportProfit(ctx, database.ReportProfitParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "product-profitability":
		return r.queries.ReportProducts(ctx, database.ReportProductsParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "transportation":
		return r.queries.ReportTransportation(ctx, database.ReportTransportationParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "shipments":
		return r.queries.ReportShipments(ctx, database.ReportShipmentsParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "inventory":
		return r.queries.ReportInventory(ctx, database.ReportInventoryParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "stock-movements":
		return r.queries.ReportMovements(ctx, database.ReportMovementsParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "damage":
		return r.queries.ReportDamage(ctx, database.ReportDamageParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "missing":
		return r.queries.ReportMissing(ctx, database.ReportMissingParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "customer-debt":
		return r.queries.ReportCustomerDebt(ctx, database.ReportCustomerDebtParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "supplier-payables":
		return r.queries.ReportSupplierPayables(ctx, database.ReportSupplierPayablesParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "expenses":
		return r.queries.ReportExpenses(ctx, database.ReportExpensesParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	case "currency-purchases":
		return r.queries.ReportCurrency(ctx, database.ReportCurrencyParams{StartOn: f.From, EndOn: f.To, PageSize: f.PageSize, PageOffset: (f.Page - 1) * f.PageSize})
	default:
		return nil, fmt.Errorf("unknown report: %s", id)
	}
}
