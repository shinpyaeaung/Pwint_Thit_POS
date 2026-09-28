import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { FormField } from '@/components/shared'
import { Field } from '../shipments/Fields'
import type { ReportFilter } from './types'
const periods = [['today', 'Today'], ['week', 'This Week'], ['month', 'This Month'], ['year', 'This Year'], ['custom', 'Custom Date Range']] as const
export function ReportFilters({ filter, resolved, onApply }: { filter: ReportFilter; resolved?: { from: string; to: string }; onApply: (filter: ReportFilter) => void }) {
  const [custom, setCustom] = useState(filter.period === 'custom')
  const [from, setFrom] = useState(filter.from || '')
  const [to, setTo] = useState(filter.to || '')
  const [error, setError] = useState('')
  function choose(period: string) {
    setError(''); setCustom(period === 'custom')
    if (period === 'custom') { setFrom(resolved?.from || from); setTo(resolved?.to || to) }
    else onApply({ period, page: 1, page_size: filter.page_size })
  }
  return <form aria-label="Report date filters" className="space-y-3" onSubmit={event => {
    event.preventDefault()
    if (!from || !to || from > to) { setError('Choose valid dates with From on or before To.'); return }
    setError(''); onApply({ period: 'custom', from, to, page: 1, page_size: filter.page_size })
  }}>
    <div className="flex flex-wrap gap-1.5" role="group" aria-label="Report period">{periods.map(([value, label]) => <Button key={value} type="button" size="sm" variant={(custom ? value === 'custom' : value === filter.period) ? 'default' : 'outline'} aria-pressed={custom ? value === 'custom' : value === filter.period} onClick={() => choose(value)}>{label}</Button>)}</div>
    {custom && <div className="flex flex-wrap items-end gap-3"><div className="w-40"><Field label="Report from" type="date" value={from} onChange={setFrom} required /></div><div className="w-40"><Field label="Report to" type="date" value={to} onChange={setTo} required /></div><Button type="submit">Apply dates</Button><p className="text-xs text-muted-foreground">Choose dates, then apply to update the report.</p></div>}
    {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
    <div className="max-w-32"><FormField label="Rows per page">{props => <Select {...props} value={filter.page_size} onValueChange={value => onApply({ ...filter, page: 1, page_size: Number(value) })}>{[10, 25, 50, 100].map(size => <SelectItem key={size} value={size}>{size}</SelectItem>)}</Select>}</FormField></div>
  </form>
}
