export const permissions = {
 expensesManage:'expenses.manage',transactionsReverse:'transactions.reverse',dashboardView:'dashboard.view',
 damageManage:'damage.manage',returnsManage:'returns.manage',refundsApprove:'refunds.approve',
 salesView: 'sales.view', customersManage: 'customers.manage', paymentsManage: 'payments.manage',
 receivingManage: 'receiving.manage',
 costsFinalize: 'costs.finalize',
  shipmentsView: 'shipments.view', shipmentsManage: 'shipments.manage', shipmentsViewCost: 'shipments.view_cost', transportationManage: 'transportation.manage', changeTransportCost: 'costs.change_transport',
  exchangeRatesManage: 'exchange_rates.manage',
  suppliersView: 'suppliers.view', suppliersCreate: 'suppliers.create', suppliersUpdate: 'suppliers.update', suppliersDelete: 'suppliers.delete',
  productsDelete: 'products.delete', catalogManage: 'catalog.manage', productsView: 'products.view', productsCreate: 'products.create', productsUpdate: 'products.update',
  purchasesView: 'purchases.view', purchasesCreate: 'purchases.create', purchasesViewCost: 'purchases.view_cost',
  inventoryView: 'inventory.view', inventoryAdjust: 'inventory.adjust', salesCreate: 'sales.create', salesDiscount: 'sales.discount',
  financeViewProfit: 'finance.view_profit', financeViewLandedCost: 'finance.view_landed_cost', reportsView: 'reports.view',
  usersManage: 'users.manage', settingsManage: 'settings.manage', permissionsManage: 'permissions.manage',
} as const
export type CurrentUser = { id: string; username: string; display_name: string; role: 'SUPER_ADMIN' | 'STAFF_ADMIN'; permissions: string[] }
export const can = (user: CurrentUser, permission: string) => user.permissions.includes(permission)
export const canAssignPermissions = (user: CurrentUser) => user.role === 'SUPER_ADMIN'
export const protectedPages: Record<string, string | null> = { '/': null, '/expenses':permissions.expensesManage,'/finance/profit':permissions.financeViewProfit, '/stock-issues':permissions.damageManage,'/returns':permissions.returnsManage, '/customers': permissions.customersManage, '/pos': permissions.salesCreate, '/sales': permissions.salesView, '/batches': permissions.inventoryView, '/receiving': permissions.receivingManage, '/receiving/new': permissions.receivingManage, '/inventory': permissions.inventoryView, '/inventory/movements': permissions.inventoryView, '/shipments': permissions.shipmentsView, '/shipments/new': permissions.shipmentsManage, '/purchases': permissions.purchasesView, '/purchases/new': permissions.purchasesCreate, '/purchasing-settings': permissions.exchangeRatesManage, '/suppliers': permissions.suppliersView, '/suppliers/new': permissions.suppliersCreate, '/products': permissions.productsView, '/products/new': permissions.productsCreate, '/catalog': permissions.catalogManage, '/users': permissions.usersManage, '/permissions': permissions.permissionsManage, '/design-system': permissions.settingsManage }

export function pagePermission(path: string): string | null | undefined {
  if (Object.hasOwn(protectedPages, path)) return protectedPages[path]
  if (/^\/customers\/[a-f0-9-]{36}$/.test(path)) return permissions.customersManage
  if (/^\/sales\/[a-f0-9-]{36}$/.test(path)) return null
  if (/^\/receiving\/[a-f0-9-]{36}$/.test(path)) return permissions.receivingManage
  if (/^\/products\/[a-f0-9-]{36}\/edit$/.test(path)) return permissions.productsUpdate
  if (/^\/products\/[a-f0-9-]{36}$/.test(path)) return permissions.productsView
  if (/^\/suppliers\/[a-f0-9-]{36}\/edit$/.test(path)) return permissions.suppliersUpdate
  if (/^\/suppliers\/[a-f0-9-]{36}$/.test(path)) return permissions.suppliersView
  if (/^\/purchases\/[a-f0-9-]{36}$/.test(path)) return permissions.purchasesView
  if (/^\/shipments\/[a-f0-9-]{36}$/.test(path)) return permissions.shipmentsView
  return undefined
}
