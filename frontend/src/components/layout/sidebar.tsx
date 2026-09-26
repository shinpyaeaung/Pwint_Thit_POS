import { ShoppingCart, PackageCheck, Boxes, Truck, Package, Tags, LayoutDashboard, ShieldCheck, Sprout, Users, PanelsTopLeft, ArrowUpRight } from 'lucide-react'
import { PermissionGuard } from '@/components/shared/permission-guard'
import { permissions, type CurrentUser } from '@/permissions'
const items = [
  { href: '/', label: 'Workspace', icon: LayoutDashboard, permission: null },
  { href: '/pos', label: 'Point of sale', icon: ShoppingCart, permission: permissions.salesCreate },
  { href: '/customers', label: 'Customers & credit', icon: ShoppingCart, permission: permissions.customersManage },
  { href: '/sales', label: 'Invoices', icon: ShoppingCart, permission: permissions.salesView },
  { href: '/products', label: 'Products', icon: Package, permission: permissions.productsView },
  { href: '/shipments', label: 'Shipments', icon: Truck, permission: permissions.shipmentsView },
  { href: '/receiving', label: 'Goods receiving', icon: PackageCheck, permission: permissions.receivingManage },
  { href: '/batches', label: 'Batches & expiry', icon: Package, permission: permissions.inventoryView },
  { href: '/inventory', label: 'Inventory', icon: Boxes, permission: permissions.inventoryView },
  { href: '/purchases', label: 'Purchases', icon: ShoppingCart, permission: permissions.purchasesView },
  { href: '/suppliers', label: 'Suppliers', icon: Truck, permission: permissions.suppliersView },
  { href: '/catalog', label: 'Catalog setup', icon: Tags, permission: permissions.catalogManage },
  { href: '/users', label: 'Users & access', icon: Users, permission: permissions.usersManage },
  { href: '/permissions', label: 'Permissions', icon: ShieldCheck, permission: permissions.permissionsManage },
  { href: '/design-system', label: 'UI library', icon: PanelsTopLeft, permission: permissions.settingsManage },
]
export function Sidebar({ user, onNavigate }: { user: CurrentUser; onNavigate?: () => void }) {
  return <div className="flex h-full flex-col"><a href="/" className="flex items-center gap-3 px-5 py-7" aria-label="Pwint Thit workspace"><span className="rounded-xl bg-primary p-2 text-white"><Sprout className="size-5" /></span><span><span className="block text-sm font-bold tracking-wide">PWINT THIT</span><span className="mt-0.5 block text-[9px] font-medium tracking-[0.22em] text-muted-foreground">DISTRIBUTION</span></span></a><nav aria-label="Main navigation" className="flex-1 space-y-1 px-3"><p className="px-3 pb-2 pt-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">Workspace & control</p>{items.map(item => {
    const active = window.location.pathname === item.href || (item.href !== '/' && window.location.pathname.startsWith(`${item.href}/`))
    const link = <a href={item.href} onClick={onNavigate} aria-current={active ? 'page' : undefined} className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-[13px] font-medium transition-colors ${active ? 'bg-primary/7 text-primary ring-1 ring-primary/10' : 'text-muted-foreground hover:bg-muted hover:text-foreground'}`}><item.icon aria-hidden="true" className="size-4" />{item.label}{active && <span className="ml-auto size-1.5 rounded-full bg-primary" />}</a>
    return item.permission ? <PermissionGuard key={item.href} user={user} permission={item.permission}>{link}</PermissionGuard> : <div key={item.href}>{link}</div>
  })}</nav><div className="m-4 rounded-xl border bg-background p-4"><p className="flex items-center justify-between text-xs font-semibold">From source to shelf<ArrowUpRight className="size-3 text-primary" /></p><p className="mt-2 text-[11px] leading-5 text-muted-foreground">Purchase · Transport · Receive · Sell</p><div className="mt-3 flex gap-1" aria-hidden="true"><span className="h-1 flex-1 rounded bg-primary" /><span className="h-1 flex-1 rounded bg-brand-yellow" /><span className="h-1 flex-1 rounded bg-border" /><span className="h-1 flex-1 rounded bg-border" /></div></div></div>
}
