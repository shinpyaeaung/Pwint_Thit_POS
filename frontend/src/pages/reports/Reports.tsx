import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { RefreshCw, ChartNoAxesCombined } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { EmptyState, FormField, LoadingState, PageHeader } from '@/components/shared'
import { requestJSON } from '@/services/api'
import type { CurrentUser } from '@/permissions'
import { ReportFilters } from './ReportFilters'
import { ReportResults } from './ReportResults'
import type { ReportDefinition, ReportFilter, ReportResponse } from './types'

export default function Reports({ current,overview=false }: { current: CurrentUser;overview?:boolean }) {
  const scope = [current.id, [...current.permissions].sort()]
  const catalog = useQuery({ queryKey: ['report-catalog', ...scope], queryFn: ({ signal }) => requestJSON<{ reports: ReportDefinition[] }>('/reports', { signal }), retry: false })
  const available=catalog.data?.reports.filter(r=>!overview||['sales','inventory','stock-movements','payments','customer-debt','supplier-payables'].includes(r.id))
  const [selected, setSelected] = useState('')
  const [filter, setFilter] = useState<ReportFilter>({ period: 'month', page: 1, page_size: 25 })
  const definition = available?.find(report => report.id === selected) || available?.find(r=>r.id==='sales') || available?.[0]
  const query = new URLSearchParams({ period: filter.period, page: String(filter.page), page_size: String(filter.page_size) })
  if (filter.period === 'custom') { query.set('from', filter.from || ''); query.set('to', filter.to || '') }
  const report = useQuery({ queryKey: ['report', ...scope, definition?.id, filter], queryFn: ({ signal }) => requestJSON<ReportResponse>(`/reports/${definition!.id}?${query}`, { signal }), enabled: !!definition, retry: false })
  return <>
    <PageHeader eyebrow="Insights / Recorded business" title={overview?"Business data":"Business reports"} description={overview?"Sales, inventory levels, inbound/outbound stock and linked payment records in one place.":"Follow sales, costs, stock and balances through your recorded business history."} actions={<Button variant="outline" disabled={!definition || report.isFetching} onClick={() => void report.refetch()}><RefreshCw className="size-4" />Refresh report</Button>} />
    {catalog.isPending ? <LoadingState label="Loading available reports…" /> : catalog.error ? <div className="panel p-5"><p role="alert" className="text-sm text-destructive">{catalog.error.message}</p><Button className="mt-3" variant="outline" onClick={() => void catalog.refetch()}>Try again</Button></div> : !definition ? <EmptyState title="No reports assigned" description="Your Super Admin can grant access to the business information you need." /> : <div className="min-w-0 space-y-5">
      <section aria-label="Report controls" className="panel grid gap-5 p-4 lg:grid-cols-[minmax(220px,1fr)_2fr]">
        <div><FormField label="Report">{props => <Select {...props} value={definition.id} onValueChange={value => { setSelected(value); setFilter({ ...filter, page: 1 }) }}>{available!.map(item => <SelectItem key={item.id} value={item.id}>{item.title}</SelectItem>)}</Select>}</FormField><p className="mt-3 flex items-center gap-2 text-xs text-muted-foreground"><ChartNoAxesCombined className="size-4 text-primary" />{available!.length} reports available</p></div>
        <ReportFilters filter={filter} resolved={report.data?.filter} onApply={setFilter} />
      </section>
      {report.isPending ? <LoadingState label="Preparing report…" /> : report.error ? <div className="panel p-5"><p role="alert" className="text-sm text-destructive">{report.error.message}</p><Button className="mt-3" variant="outline" onClick={() => void report.refetch()}>Try again</Button></div> : report.data && <ReportResults report={report.data} onPageChange={page => setFilter({ ...filter, page })} />}
    </div>}
  </>
}
