import { MoneyChart } from '@/components/charts/money-chart'
import { useQuery } from '@tanstack/react-query'
import { ArrowUpRight, RefreshCw, Package, TriangleAlert, Receipt, CircleDollarSign } from 'lucide-react'
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
  const hasAlerts = Boolean(data.total)
  return <section className="panel flex flex-col justify-between p-4" aria-label={title}>
    <div>
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold tracking-tight text-foreground">{title}</h2>
        <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold tabular-nums ${hasAlerts ? 'bg-amber-100 text-amber-800' : 'bg-muted text-muted-foreground'}`}>{data.total}</span>
      </div>
      <p className="mb-3 mt-1 text-xs leading-5 text-muted-foreground">{note}</p>
      {data.expired !== undefined && data.expired > 0 && <div className="mb-2.5 inline-flex items-center gap-1.5 rounded-lg bg-red-50 px-2.5 py-1 text-xs font-medium text-primary"><span className="size-1.5 rounded-full bg-primary" />{data.expired} batches already expired</div>}
      {data.items.length ? (
        <ul className="divide-y divide-border">{data.items.map(row => (
          <li key={row.id} className="py-2.5 transition-colors first:pt-0 hover:bg-background/50">
            <div className="flex justify-between gap-3 text-xs">
              <span className="min-w-0 break-words font-medium text-foreground">{row.name}</span>
              <span className="shrink-0 font-semibold tabular-nums text-foreground">{amount(row.quantity)} {row.unit}</span>
            </div>
            <p className="mt-1 text-xs text-muted-foreground">{row.minimum !== undefined ? `Minimum ${amount(row.minimum)} ${row.unit}` : row.expires_on ? `${row.batch_number} · ${row.expires_on}` : 'In damaged stock'}</p>
          </li>
        ))}</ul>
      ) : (
        <p className="py-6 text-center text-xs text-muted-foreground">No items need attention.</p>
      )}
    </div>
    <a href={href} className="mt-4 inline-flex items-center gap-1.5 text-xs font-semibold text-primary transition-colors hover:underline">Review all <ArrowUpRight className="size-3.5" /></a>
  </section>
}

export default function Dashboard({ current }: { current: CurrentUser }) {
  const query = useQuery({ queryKey: ['dashboard', current.id, [...current.permissions].sort()], queryFn: ({ signal }) => requestJSON<Snapshot>('/dashboard', { signal }), refetchInterval: 60000, staleTime: 15000, retry: false })
  const d = query.data
  const month = d?.profit?.month
  return <>
    <PageHeader eyebrow="Overview / Live business" title="Distribution dashboard" description={d ? `${d.business_date} · Myanmar business day · MMK` : 'Your daily sales, costs and stock in one place.'} actions={<div className="flex items-center gap-2.5"><Button variant="outline" disabled={query.isFetching} onClick={() => void query.refetch()}><RefreshCw className="size-3.5" />Refresh</Button>{can(current, permissions.salesCreate) && <Button asChild><a href="/pos">Open POS <ArrowUpRight className="size-4" /></a></Button>}</div>} />
    {query.isPending && <LoadingState label="Loading business snapshot…" />}
    {query.error && <p role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-900">{d ? 'The snapshot below may be out of date. ' : ''}{query.error.message}</p>}
    {d && <div className="space-y-5">
      {/* Top Metrics Cards */}
      <div className="grid border-y bg-surface md:grid-cols-3">
        {d.sales && (
          <section className="min-w-0 border-b p-5 md:col-span-2 md:border-b-0 md:border-r" aria-label="Sales overview">
            <div className="flex items-center justify-between gap-3">
              <div className="text-xs font-semibold text-muted-foreground">
                Today's sales
              </div>

            </div>
            <p className="mt-4 break-words text-3xl font-semibold tracking-tight tabular-nums text-foreground sm:text-3xl" data-testid="today-sales">{mmk(d.sales.today_mmk)}</p>
            <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-border pt-3.5 text-sm">
              <span className="font-medium text-muted-foreground">Monthly Sales</span>
              <strong className="text-base font-semibold tabular-nums text-foreground">{mmk(d.sales.month_mmk)}</strong>
            </div>
            <p className="mt-1.5 text-xs text-muted-foreground">Net sales after returns, including credit sales.</p>
          </section>
        )}
        {d.profit && (
          <section className="min-w-0 p-5" aria-label="Today's profit">
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-semibold  text-amber-900">Today's Profit</p>

            </div>
            <p className={`mt-4 break-words text-2xl font-semibold tracking-tight tabular-nums sm:text-3xl ${d.profit.today.net_profit_mmk?.startsWith('-') ? 'text-primary' : 'text-foreground'}`}>{mmk(d.profit.today.net_profit_mmk)}</p>
            <p className="mt-4 text-xs leading-5 text-muted-foreground">After actual landed cost and today's operating expenses.</p>
            {d.profit.today.incomplete_cost_sales > 0 && <p className="mt-2 text-xs font-medium text-primary">Incomplete sale costs; profit withheld.</p>}
          </section>
        )}
      </div>

      {/* Monthly Performance & Balances Grid */}
      <div className="grid items-start gap-5 lg:grid-cols-[1.5fr_1fr]">
        {month && (
          <section className="panel min-w-0 overflow-hidden p-0" aria-label="Monthly profit">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border bg-muted px-5 py-4">
              <div>
                <h2 className="text-sm font-semibold tracking-tight text-foreground">This month's performance</h2>
                <p className="text-xs text-muted-foreground">Operating summary for the active period</p>
              </div>
              <a href="/finance/profit" className="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline">View profit report ↗</a>
            </div>
            <MoneyChart embedded title="Monthly revenue & costs" scope={`${d.business_date.slice(0,7)} · month to date`} series={[
              {label:'Net sales',exact:month.revenue_mmk}, {label:'Cost of goods sold',exact:month.cogs_mmk},
              {label:'Gross Profit',exact:month.gross_profit_mmk}, {label:'Operating expenses',exact:month.expenses_mmk},
              {label:'Net Profit',exact:month.net_profit_mmk,accent:true},
            ]}/>

            {month.incomplete_cost_sales > 0 && <p role="alert" className="border-t border-border px-5 py-3 text-xs font-medium text-primary bg-red-50/50">{month.incomplete_cost_sales} sales have incomplete actual cost. Profit is unavailable.</p>}
          </section>
        )}
        <div className="min-w-0 space-y-5">
          {d.inventory_value && (
            <section className="panel p-5" aria-label="Inventory value">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 text-xs font-semibold  text-muted-foreground">
                  <Package className="size-4 text-muted-foreground" />
                  Inventory Value
                </div>
              </div>
              <p className="mt-3 break-words text-2xl font-semibold tracking-tight tabular-nums text-foreground">{mmk(d.inventory_value.amount_mmk)}</p>
              <p className="mt-2 text-xs leading-5 text-muted-foreground">Sellable stock at landed cost, including reserved and expired stock awaiting disposal. Damaged stock excluded.</p>
              {d.inventory_value.incomplete_batches > 0 && <p className="mt-2 text-xs font-medium text-primary">Cost incomplete for {d.inventory_value.incomplete_batches} stock positions; total withheld.</p>}
            </section>
          )}
          {(d.customer_debt_mmk !== undefined || d.supplier_debt_mmk !== undefined) && (
            <section className="rounded-lg border border-border bg-surface p-5" aria-label="Outstanding balances">
              <div className="flex items-center gap-2">
                <CircleDollarSign className="size-4 text-muted-foreground" />
                <h2 className="text-xs font-semibold  text-muted-foreground">Outstanding balances</h2>
              </div>
              <MoneyChart embedded title="Receivables & payables" scope="Current outstanding balances" series={[
                ...(d.customer_debt_mmk!==undefined?[{label:'Customer Debt',exact:d.customer_debt_mmk}]:[]),
                ...(d.supplier_debt_mmk!==undefined?[{label:'Supplier Debt',exact:d.supplier_debt_mmk}]:[]),
              ]}/>

              <p className="mt-4 text-xs leading-5 text-muted-foreground">Unpaid invoice balances after payments, credits and refunds. Supplier balances retain transaction rates.</p>
            </section>
          )}
        </div>
      </div>

      <p className="text-xs text-muted-foreground">Historical sales and profit trends are unavailable in this snapshot. Use Reports to compare recorded periods.</p>

      {/* Stock Attention Alerts */}
      {(d.low_stock || d.expiring || d.damaged) && (
        <div>
          <div className="mb-3.5 flex items-center gap-2">
            <TriangleAlert className="size-4 text-amber-600" />
            <h2 className="text-xs font-semibold  text-muted-foreground">Stock attention</h2>
          </div>
          <div className="grid items-start gap-4 md:grid-cols-3">
            {d.low_stock && <StockAlerts title="Low Stock" data={d.low_stock} note="Products at or below minimum; eligible, unreserved units across warehouses." href="/inventory" />}
            {d.expiring && <StockAlerts title="Expiring Products" data={d.expiring} note="Stocked batches expired or due within 60 days, earliest first." href="/batches" />}
            {d.damaged && <StockAlerts title="Damaged Products" data={d.damaged} note="Products currently held in damaged stock." href="/stock-issues" />}
          </div>
        </div>
      )}

      {/* Recent Transactions Panel */}
      <section className="panel min-w-0 overflow-hidden p-0" aria-label="Recent transactions">
        <div className="flex items-center justify-between border-b border-border bg-muted px-5 py-4">
          <div>
            <h2 className="text-sm font-semibold tracking-tight text-foreground">Recent Transactions</h2>
            <p className="text-xs text-muted-foreground">Latest posted records visible to your account.</p>
          </div>
          <Receipt className="size-4 text-muted-foreground" />
        </div>
        {d.recent.length ? (
          <ul className="divide-y divide-border">{d.recent.map(row => (
            <li key={`${row.kind}-${row.id}`}>
              <a href={row.href} className="group flex flex-wrap items-center justify-between gap-3 px-5 py-3 text-sm transition-colors hover:bg-background/80">
                <div className="flex items-center gap-3 min-w-0 flex-1">
                  <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-muted text-muted-foreground transition-colors group-hover:bg-primary/10 group-hover:text-primary">
                    <Receipt className="size-3.5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="break-words font-semibold text-foreground group-hover:text-primary transition-colors">{row.label}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">{row.kind} · {time(row.occurred_at)}</p>
                  </div>
                </div>
                <span className="break-words text-right text-sm font-semibold tabular-nums text-foreground">{mmk(row.amount_mmk)}</span>
              </a>
            </li>
          ))}</ul>
        ) : (
          <p className="px-5 py-10 text-center text-sm text-muted-foreground">No posted transactions available for your permissions.</p>
        )}
      </section>

      {!d.sales && !d.profit && !d.low_stock && !d.damaged && d.customer_debt_mmk === undefined && d.supplier_debt_mmk === undefined && (
        <p className="text-sm text-muted-foreground">Your dashboard is ready. Ask your Super Admin to assign access to the business information you need.</p>
      )}
      <p className="text-xs text-muted-foreground">Snapshot {time(d.as_of)} · Refreshes every minute. Profit uses recorded operating expenses; damage/missing estimates are separate.</p>
    </div>}
  </>
}
