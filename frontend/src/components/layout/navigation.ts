import { type LucideIcon, BookOpen, Boxes, ChartNoAxesCombined, CircleDollarSign, ClipboardList, Coins, LayoutDashboard, Package, PackageCheck, Receipt, RotateCcw, ShieldCheck, ShoppingCart, Tags, TriangleAlert, Truck, Users } from 'lucide-react'
import { can, permissions, type CurrentUser } from '@/permissions'

export type NavigationItem = { href: string; label: string; icon: LucideIcon; permission?: string; additionalPermission?:string }
type ProtectedLink = NavigationItem & { permission: string }

export const overviewLinks: ProtectedLink[] = [
  { href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard, permission: permissions.dashboardView },
  { href: '/reports', label: 'Reports', icon: ChartNoAxesCombined, permission: permissions.reportsView },
]
export const navigationGroups: { title: string; items: ProtectedLink[] }[] = [
  { title: 'Sales', items: [
    { href: '/pos', label: 'Point of sale', icon: ShoppingCart, permission: permissions.salesCreate },
    { href: '/sales', label: 'Invoices', icon: Receipt, permission: permissions.salesView },
    { href: '/customers', label: 'Customers & credit', icon: Users, permission: permissions.customersManage },
    { href: '/returns', label: 'Returns & refunds', icon: RotateCcw, permission: permissions.returnsManage },
  ] },
  { title: 'Products & stock', items: [
    { href: '/products', label: 'Products', icon: Package, permission: permissions.productsView },
    { href: '/inventory', label: 'Inventory', icon: Boxes, permission: permissions.inventoryView },
    { href: '/batches', label: 'Batches & expiry', icon: ClipboardList, permission: permissions.inventoryView },
    { href: '/stock-issues', label: 'Damage & missing', icon: TriangleAlert, permission: permissions.damageManage },
    { href:'/warehouse-prices',label:'Warehouse prices',icon:Tags,permission:permissions.productsUpdate },
    { href: '/catalog', label: 'Catalog setup', icon: Tags, permission: permissions.catalogManage },
  ] },
  { title: 'Purchasing', items: [
    { href: '/suppliers', label: 'Suppliers', icon: Users, permission: permissions.suppliersView },
    { href: '/purchases', label: 'Purchases', icon: ShoppingCart, permission: permissions.purchasesView },
    { href: '/shipments', label: 'Shipments', icon: Truck, permission: permissions.shipmentsView },
    { href: '/transfers/new', label:'Ship between warehouses',icon:Truck,permission:'stock_transfers.manage' },
    { href: '/receiving', label: 'Goods receiving', icon: PackageCheck, permission: permissions.receivingManage },
    { href: '/purchasing-settings', label: 'Currency & rates', icon: Coins, permission: permissions.exchangeRatesManage },
  ] },
  { title: 'Payments', items: [
    { href: '/supplier-payments', label: 'Supplier Payments', icon: Coins, permission: permissions.purchasesViewCost, additionalPermission:permissions.purchasesView },

 { href:'/payments',label:'Payment centre',icon:Coins,permission:permissions.paymentsManage },
 ] },
 { title: 'Finance', items: [
 {href:'/business-data',label:'Business data',icon:ClipboardList,permission:permissions.reportsView},
 {href:'/assistant',label:'AI assistant demo',icon:ChartNoAxesCombined,permission:permissions.reportsView},

    { href: '/expenses', label: 'Operating expenses', icon: Receipt, permission: permissions.expensesManage },
    { href: '/finance/profit', label: 'Expenses & profit', icon: CircleDollarSign, permission: permissions.financeViewProfit },
  ] },
  { title: 'Administration', items: [
    { href: '/users', label: 'Users & access', icon: Users, permission: permissions.usersManage },
    { href: '/permissions', label: 'Permissions', icon: ShieldCheck, permission: permissions.permissionsManage },
  ] },
]
export const guideLink = { href: '/guide', label: 'User guide', icon: BookOpen }
export const visibleNavigation = (user: CurrentUser) => [...overviewLinks, ...navigationGroups.flatMap(group => group.items)].filter(item => can(user, item.permission)&&(!item.additionalPermission||can(user,item.additionalPermission)))
