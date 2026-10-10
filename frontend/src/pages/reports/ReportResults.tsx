import { DataTable, EmptyState } from '@/components/shared'
import { amount } from '../purchases/types'
import type { ReportColumn, ReportResponse, ReportRow } from './types'
const timestamp = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Yangon', year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' })
function reportValue(value: string | number | null | undefined, kind: ReportColumn['kind']) {
  if (value === null || value === undefined) return kind === 'money' ? 'Unavailable' : '—'
  if (kind === 'money') return `${amount(String(value))} MMK`
  if (kind === 'decimal') return amount(String(value))
  if (kind === 'datetime') return timestamp.format(new Date(String(value)))
  return String(value)
}
export function ReportResults({ report, onPageChange }: { report: ReportResponse; onPageChange: (page: number) => void }) {
  const { definition, filter } = report
  const incomplete = Object.entries(report.summary).some(([key, value]) => key.startsWith('incomplete_cost') && String(value) !== '0')
  return <div className="space-y-4" aria-label="Report results">
    <div className="flex flex-wrap items-baseline justify-between gap-2"><h2 className="text-base font-semibold">{definition.title}</h2><p className="text-xs text-muted-foreground" data-testid="report-range">{filter.from} — {filter.to} · Asia/Yangon · MMK</p></div>
    <p className="max-w-4xl text-xs leading-5 text-muted-foreground">{definition.description}</p>
    {incomplete && <p role="alert" className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">Some sales have incomplete landed costs. Affected profit amounts are unavailable.</p>}
    <dl className={`grid gap-3 ${definition.metrics.length === 1 ? 'max-w-sm grid-cols-1' : 'sm:grid-cols-2 xl:grid-cols-4'}`} aria-label="Report totals">{definition.metrics.map(metric => <div key={metric.key} className="min-w-0 rounded-xl border bg-white p-4"><dt className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">{metric.label}</dt><dd data-testid={`report-total-${metric.key}`} className={`mt-2 break-words text-xl font-semibold tabular-nums ${String(report.summary[metric.key]).startsWith('-') ? 'text-primary' : ''}`}>{reportValue(report.summary[metric.key], metric.kind)}</dd></div>)}</dl>
    <p className="text-[11px] text-muted-foreground">Totals cover all {report.total} matching records. Tables show one page at a time.</p>
    <DataTable<ReportRow> caption={definition.title} rows={report.rows} rowKey={row => `${row.id}:${row.event_type||''}`} columns={definition.columns.map(column => ({ id: column.key, header: column.label, align: column.kind === 'money' || column.kind === 'decimal' ? 'right' : 'left', cell: row => <span className={column.kind === 'money' || column.kind === 'decimal' ? 'whitespace-nowrap' : 'block min-w-24 max-w-64 break-words'}>{reportValue(row[column.key], column.kind)}</span> }))} pagination={{ page: filter.page, pageSize: filter.page_size, total: report.total, onPageChange }} empty={<EmptyState title="No records in this period" description="Choose a different date range to review business activity." />} />
  </div>
}
