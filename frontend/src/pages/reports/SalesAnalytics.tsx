import { lazy, Suspense } from 'react'
import { ChartBoundary } from '@/components/charts/chart-boundary'
const PerformanceChart=lazy(()=>import('./SalesPerformanceChart'))
import { MoneyChart } from '@/components/charts/money-chart'
import type { ReportResponse } from './types'
export function SalesAnalytics({report}:{report:ReportResponse}) {
 const data=report.analytics!
 const scope=`Complete period · ${report.filter.from} — ${report.filter.to} · Myanmar time`
 return <section aria-label="Sales analytics" className="space-y-4"><MoneyChart title="Best-selling products — net revenue" scope={`${scope} · top 10 by sold base-unit quantity; see quantities and units below`} series={data.top_products.map(r=>({label:`${r.rank}. ${r.product}`,exact:r.revenue_mmk}))}/><div className="grid min-w-0 gap-4 xl:grid-cols-2"><ChartBoundary><Suspense fallback={<p>Loading sales charts…</p>}><PerformanceChart title="Sales by date" scope={`${scope} · days with activity; missing dates have no sales or returns`} series={data.daily.map(r=>({label:r.day!,exact:r.revenue_mmk}))}/></Suspense></ChartBoundary><ChartBoundary><Suspense fallback={<p>Loading sales charts…</p>}><PerformanceChart title="Sales by hour" scope={`${scope} · net revenue by hour of day, across all selected dates`} series={data.hourly.map(r=>({label:`${r.hour!.padStart(2,'0')}:00`,exact:r.revenue_mmk}))}/></Suspense></ChartBoundary></div></section>
}
