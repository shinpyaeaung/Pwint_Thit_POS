import { lazy, Suspense } from 'react'
import { ChartBoundary } from './chart-boundary'
import { amount } from '@/pages/purchases/types'
import { chartData, type MoneySeries } from './chart-data'
const Plot = lazy(() => import('./money-plot'))

export function MoneyChart({ title, scope, series, embedded = false }: { title: string; scope: string; series: MoneySeries[]; embedded?: boolean }) {
  const data = chartData(series)
  return <figure aria-label={title} className={`${embedded ? '' : 'panel'} min-w-0 p-4`} data-testid="money-chart">
    <figcaption className="mb-3"><h3 className="text-sm font-semibold">{title}</h3><p className="mt-1 text-xs leading-5 text-muted-foreground">{scope} · MMK</p></figcaption>
    {data.length ? <><ChartBoundary><Suspense fallback={<p role="status" className="py-10 text-xs text-muted-foreground">Loading chart…</p>}><Plot data={data}/></Suspense></ChartBoundary>{data.every(row=>row.geometry===0)&&<p className="text-xs text-muted-foreground">All displayed amounts are zero.</p>}</> : <p className="py-5 text-sm text-muted-foreground">No recorded amounts available to chart.</p>}
    {data.length < series.length && <p className="mt-2 text-xs text-muted-foreground">Unavailable amounts are omitted from the plot, not treated as zero.</p>}
    {series.length > 0 && <details className="mt-3 border-t pt-3"><summary className="cursor-pointer text-xs font-medium">Exact chart values</summary><dl className="mt-2 divide-y" data-testid="chart-values">{series.map((row,index)=><div key={`${row.label}-${index}`} className="flex flex-wrap justify-between gap-2 py-2 text-xs"><dt className="min-w-0 break-words">{row.label}</dt><dd className="break-all text-right tabular-nums">{row.exact === null ? 'Unavailable' : `${amount(row.exact)} MMK`}</dd></div>)}</dl></details>}
  </figure>
}
