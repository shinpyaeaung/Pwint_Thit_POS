import { useQuery } from '@tanstack/react-query'
import { ArrowUpRight, RefreshCw, Package, TriangleAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { LoadingState, PageHeader } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import { mmk, type ProfitSummary } from './finance/types'
import { amount } from './purchases/types'

type StockRow = { id: string; name: string; quantity: string; unit: string; minimum?: string; batch_number?: string; expires_on?: string }
type Alerts = { total: number; expired?: number; items: StockRow[] }
type Snapshot = {
  business_date: string; as_of: string
  sales?: { today_mmk: string; month_mmk: string }
  profit?: { today: ProfitSummary; month: ProfitSummary }
  inventory_value?: { amount_mmk: string | null; incomplete_batches: number }
  customer_debt_mmk?: string; supplier_debt_mmk?: string
  low_stock?: Alerts; expiring?: Alerts; damaged?: Alerts
  recent: { id: string; kind: string; label: string; occurred_at: string; amount_mmk: string; href: string }[]
}
const time = (v: string) => new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Yangon', hour: '2-digit', minute: '2-digit', day: '2-digit', month: 'short' }).format(new Date(v))
function StockAlerts({ title, data, note, href }: { title: string; data: Alerts; note: string; href: string }) {
  return <section className="panel min-w-0 p-4" aria-label={title}>
    <div className="flex items-center justify-between gap-3"><h2 className="text-sm font-semibold">{title}</h2><span className={`rounded-md px-2 py-1 text-xs font-bold ${data.total ? 'bg-amber-50 text-amber-900' : 'bg-muted'}`}>{data.total}</span></div>
    <p className="mb-3 mt-1 text-[11px] leading-5 text-muted-foreground">{note}</p>
    {data.expired !== undefined && data.expired > 0 && <p className="mb-2 text-xs font-medium text-primary">{data.expired} batches already expired</p>}
    {data.items.length ? <ul className="divide-y">{data.items.map(row => <li key={row.id} className="py-2.5"><div className="flex justify-between gap-3 text-xs"><span className="min-w-0 break-words font-medium">{row.name}</span><span className="shrink-0 tabular-nums">{amount(row.quantity)} {row.unit}</span></div><p className="mt-1 text-[11px] text-muted-foreground">{row.minimum !== undefined ? `Minimum ${amount(row.minimum)} ${row.unit}` : row.expires_on ? `${row.batch_number} · ${row.expires_on}` : 'In damaged stock'}</p></li>)}</ul> : <p className="py-5 text-xs text-muted-foreground">No items need attention.</p>}
    <a href={href} className="mt-3 inline-flex items-center gap-1 text-xs font-medium text-primary">Review all <ArrowUpRight className="size-3" /></a>
  </section>
}
export default function Dashboard({ current }: { current: CurrentUser }) {
  const query = useQuery({ queryKey: ['dashboard', current.id, [...current.permissions].sort()], queryFn: ({ signal }) => requestJSON<Snapshot>('/dashboard', { signal }), refetchInterval: 60000, staleTime: 15000, retry: false })
  const d = query.data
  const month = d?.profit?.month
  return <>
    <PageHeader eyebrow="Overview / Live business" title="Distribution dashboard" description={d ? `${d.business_date} · Myanmar business day · MMK` : 'Your daily sales, costs and stock in one place.'} actions={<div className="flex gap-2"><Button variant="outline" disabled={query.isFetching} onClick={() => void query.refetch()}><RefreshCw className="size-4" />Refresh</Button>{can(current, permissions.salesCreate) && <Button asChild><a href="/pos">Open POS <ArrowUpRight className="size-4" /></a></Button>}</div>} />
    {query.isPending && <LoadingState label="Loading business snapshot…" />}
    {query.error && <p role="alert" className="mb-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-900">{d ? 'The snapshot below may be out of date. ' : ''}{query.error.message}</p>}
    {d && <div className="space-y-5">
      <div className="grid gap-4 md:grid-cols-3">
        {d.sales && <section className="min-w-0 rounded-xl border border-primary/15 bg-white p-5 md:col-span-2" aria-label="Sales overview"><div className="flex items-center gap-2 text-xs font-semibold text-primary"><span className="size-1.5 rounded-full bg-primary" />TODAY'S SALES</div><p className="mt-3 break-words text-3xl font-bold tracking-tight tabular-nums" data-testid="today-sales">{mmk(d.sales.today_mmk)}</p><div className="mt-5 flex flex-wrap items-center justify-between gap-2 border-t pt-3 text-sm"><span className="text-muted-foreground">Monthly Sales</span><strong className="tabular-nums">{mmk(d.sales.month_mmk)}</strong></div><p className="mt-2 text-[11px] text-muted-foreground">Net sales after returns, including credit sales.</p></section>}
        {d.profit && <section className="min-w-0 rounded-xl border bg-amber-50/60 p-5" aria-label="Today's profit"><p className="text-xs font-semibold uppercase tracking-wide">Today's Profit</p><p className={`mt-3 break-words text-2xl font-bold tabular-nums ${d.profit.today.net_profit_mmk?.startsWith('-') ? 'text-primary' : ''}`}>{mmk(d.profit.today.net_profit_mmk)}</p><p className="mt-3 text-xs leading-5 text-muted-foreground">After actual landed cost and today's operating expenses.</p>{d.profit.today.incomplete_cost_sales > 0 && <p className="mt-2 text-xs text-primary">Incomplete sale costs; profit withheld.</p>}</section>}
      </div>
      <div className="grid items-start gap-5 lg:grid-cols-[1.5fr_1fr]">
        {month && <section className="panel min-w-0 overflow-hidden" aria-label="Monthly profit"><div className="flex flex-wrap items-center justify-between gap-2 border-b px-5 py-4"><h2 className="text-sm font-semibold">This month's performance</h2><a href="/finance/profit" className="text-xs text-primary">View profit report ↗</a></div><dl className="px-5 py-3">{[['Net sales', month.revenue_mmk], ['Cost of goods sold', month.cogs_mmk], ['Gross Profit', month.gross_profit_mmk], ['Operating expenses', month.expenses_mmk], ['Net Profit', month.net_profit_mmk]].map(([label, value]) => <div key={label} className={`flex flex-wrap justify-between gap-2 py-3 text-sm ${label === 'Net Profit' ? 'border-t text-lg font-bold' : label === 'Gross Profit' ? 'border-t font-semibold' : 'text-muted-foreground'}`}><dt>{label}</dt><dd className={`tabular-nums ${value?.startsWith('-') ? 'text-primary' : ''}`}>{mmk(value)}</dd></div>)}</dl>{month.incomplete_cost_sales > 0 && <p role="alert" className="px-5 pb-4 text-xs text-primary">{month.incomplete_cost_sales} sales have incomplete actual cost. Profit is unavailable.</p>}</section>}
        <div className="min-w-0 space-y-4">
          {d.inventory_value && <section className="panel p-5" aria-label="Inventory value"><div className="flex items-center gap-2 text-sm font-semibold"><Package className="size-4 text-muted-foreground" />Inventory Value</div><p className="mt-3 break-words text-xl font-bold tabular-nums">{mmk(d.inventory_value.amount_mmk)}</p><p className="mt-2 text-xs leading-5 text-muted-foreground">Sellable stock at landed cost, including reserved and expired stock awaiting disposal. Damaged stock excluded.</p>{d.inventory_value.incomplete_batches > 0 && <p className="mt-2 text-xs text-primary">Cost incomplete for {d.inventory_value.incomplete_batches} stock positions; total withheld.</p>}</section>}
          {(d.customer_debt_mmk !== undefined || d.supplier_debt_mmk !== undefined) && <section className="rounded-xl border border-dashed p-5" aria-label="Outstanding balances"><h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-muted-foreground">Outstanding balances</h2><dl className="space-y-4">{[['Customer Debt', d.customer_debt_mmk], ['Supplier Debt', d.supplier_debt_mmk]].map(([label, value]) => value !== undefined && <div key={label}><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-1 break-words text-lg font-semibold tabular-nums">{mmk(value)}</dd></div>)}</dl><p className="mt-3 text-[11px] leading-5 text-muted-foreground">Unpaid invoice balances after payments, credits and refunds. Supplier balances retain transaction rates.</p></section>}
        </div>
      </div>
      {(d.low_stock || d.expiring || d.damaged) && <div><h2 className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground"><TriangleAlert className="size-3.5" />Stock attention</h2><div className="grid items-start gap-4 md:grid-cols-3">{d.low_stock && <StockAlerts title="Low Stock" data={d.low_stock} note="Products at or below minimum; eligible, unreserved units across warehouses." href="/inventory" />}{d.expiring && <StockAlerts title="Expiring Products" data={d.expiring} note="Stocked batches expired or due within 60 days, earliest first." href="/batches" />}{d.damaged && <StockAlerts title="Damaged Products" data={d.damaged} note="Products currently held in damaged stock." href="/stock-issues" />}</div></div>}
      <section className="panel min-w-0 overflow-hidden" aria-label="Recent transactions"><div className="border-b px-5 py-4"><h2 className="text-sm font-semibold">Recent Transactions</h2><p className="mt-1 text-xs text-muted-foreground">Latest posted records visible to your account.</p></div>{d.recent.length ? <ul className="divide-y px-5">{d.recent.map(row => <li key={`${row.kind}-${row.id}`}><a href={row.href} className="flex flex-wrap items-center justify-between gap-2 py-3 text-sm hover:text-primary"><div className="min-w-0 flex-1"><p className="break-words font-medium">{row.label}</p><p className="mt-1 text-[11px] text-muted-foreground">{row.kind} · {time(row.occurred_at)}</p></div><span className="break-words text-right text-xs font-semibold tabular-nums">{mmk(row.amount_mmk)}</span></a></li>)}</ul> : <p className="px-5 py-8 text-sm text-muted-foreground">No posted transactions available for your permissions.</p>}</section>
      {!d.sales && !d.profit && !d.low_stock && !d.damaged && d.customer_debt_mmk === undefined && d.supplier_debt_mmk === undefined && <p className="text-sm text-muted-foreground">Your dashboard is ready. Ask your Super Admin to assign access to the business information you need.</p>}
      <p className="text-[11px] text-muted-foreground">Snapshot {time(d.as_of)} · Refreshes every minute. Profit uses recorded operating expenses; damage/missing estimates are separate.</p>
    </div>}
  </>
}
