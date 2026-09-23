import { useState, type ReactNode } from 'react'
import { ArrowDown, ArrowUp, ChevronsUpDown } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { EmptyState } from './empty-state'
import { LoadingState } from './loading-state'
export type Column<T> = { id: string; header: string; cell: (row: T) => ReactNode; compare?: (a: T, b: T) => number; align?: 'left' | 'right' }
export function DataTable<T>({ columns, rows, rowKey, caption, loading, error, onRetry, empty, pageSize = 10, pagination }: { columns: Column<T>[]; rows: T[]; rowKey: (row: T) => string; caption: string; loading?: boolean; error?: string; onRetry?: () => void; empty?: ReactNode; pageSize?: number; pagination?: { page: number; pageSize: number; total: number; onPageChange: (page: number) => void } }) {
  const [sort, setSort] = useState<{ id: string; desc: boolean } | null>(null)
  const [page, setPage] = useState(0)
  const size = Math.max(1, Math.floor(pagination?.pageSize || pageSize))
  const total = pagination?.total ?? rows.length
  const pages = Math.max(1, Math.ceil(total / size))
  const current = pagination ? pagination.page - 1 : Math.min(page, pages - 1)
  const column = columns.find(c => c.id === sort?.id)
  const sorted = column?.compare ? [...rows].sort((a, b) => column.compare!(a, b) * (sort?.desc ? -1 : 1)) : rows
  if (loading) return <div className="panel"><LoadingState /></div>
  if (error) return <div className="panel p-6"><p role="alert" className="text-sm text-destructive">{error}</p>{onRetry && <Button variant="outline" className="mt-4" onClick={onRetry}>Try again</Button>}</div>
  return <div className="panel overflow-hidden">{rows.length === 0 ? empty || <EmptyState description="Try another search or adjust your filters." /> : <><div className="max-h-[34rem] overflow-auto" tabIndex={0} role="region" aria-label={`${caption} table`}><table className="w-full text-left text-sm"><caption className="sr-only">{caption}</caption><thead className="sticky top-0 z-10 bg-muted"><tr>{columns.map(c => <th key={c.id} scope="col" aria-sort={c.compare ? sort?.id === c.id ? sort.desc ? 'descending' : 'ascending' : 'none' : undefined} className={`whitespace-nowrap border-b px-4 py-3 text-xs font-medium text-muted-foreground ${c.align === 'right' ? 'text-right' : ''}`}>{c.compare ? <button className="inline-flex items-center gap-2 rounded focus-visible:outline-2 focus-visible:outline-primary" onClick={() => { setSort({ id: c.id, desc: sort?.id === c.id ? !sort.desc : false }); setPage(0) }}>{c.header}{sort?.id === c.id ? sort.desc ? <ArrowDown className="size-3" /> : <ArrowUp className="size-3" /> : <ChevronsUpDown className="size-3" />}</button> : c.header}</th>)}</tr></thead><tbody>{(pagination ? sorted : sorted.slice(current * size, (current + 1) * size)).map(row => <tr key={rowKey(row)} className="border-b last:border-0 hover:bg-muted/50">{columns.map(c => <td key={c.id} className={`px-4 py-3 ${c.align === 'right' ? 'text-right tabular-nums' : ''}`}>{c.cell(row)}</td>)}</tr>)}</tbody></table></div><div className="flex flex-wrap items-center justify-between gap-3 border-t px-4 py-3 text-xs text-muted-foreground"><span>{current * size + 1}–{Math.min((current + 1) * size, total)} of {total} records</span><div className="flex items-center gap-2"><Button size="sm" variant="outline" disabled={current === 0} onClick={() => pagination ? pagination.onPageChange(current) : setPage(current - 1)}>Previous</Button><span>Page {current + 1} of {pages}</span><Button size="sm" variant="outline" disabled={current + 1 >= pages} onClick={() => pagination ? pagination.onPageChange(current + 2) : setPage(current + 1)}>Next</Button></div></div></>}</div>
}
