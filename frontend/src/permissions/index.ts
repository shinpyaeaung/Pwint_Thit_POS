export const permissions = {
  productsDelete: 'products.delete', catalogManage: 'catalog.manage', productsView: 'products.view', productsCreate: 'products.create', productsUpdate: 'products.update',
  purchasesView: 'purchases.view', purchasesCreate: 'purchases.create', purchasesViewCost: 'purchases.view_cost',
  inventoryView: 'inventory.view', inventoryAdjust: 'inventory.adjust', salesCreate: 'sales.create', salesDiscount: 'sales.discount',
  financeViewProfit: 'finance.view_profit', financeViewLandedCost: 'finance.view_landed_cost', reportsView: 'reports.view',
  usersManage: 'users.manage', settingsManage: 'settings.manage', permissionsManage: 'permissions.manage',
} as const
export type CurrentUser = { id: string; username: string; display_name: string; role: 'SUPER_ADMIN' | 'STAFF_ADMIN'; permissions: string[] }
export const can = (user: CurrentUser, permission: string) => user.permissions.includes(permission)
export const canAssignPermissions = (user: CurrentUser) => user.role === 'SUPER_ADMIN'
export const protectedPages: Record<string, string | null> = { '/': null, '/products': permissions.productsView, '/products/new': permissions.productsCreate, '/catalog': permissions.catalogManage, '/users': permissions.usersManage, '/permissions': permissions.permissionsManage, '/design-system': permissions.settingsManage }

export function pagePermission(path: string): string | null | undefined {
  if (Object.hasOwn(protectedPages, path)) return protectedPages[path]
  if (/^\/products\/[a-f0-9-]{36}\/edit$/.test(path)) return permissions.productsUpdate
  if (/^\/products\/[a-f0-9-]{36}$/.test(path)) return permissions.productsView
  return undefined
}
