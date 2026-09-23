import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { requestJSON } from '@/services/api'
import { PageHeader, DataTable, FilterBar, SearchInput, StatusBadge } from '@/components/shared'
export type Permission = { code: string; description: string; sensitive: boolean }
export default function Permissions() {
  const [search, setSearch] = useState('')
  const [sensitive, setSensitive] = useState(false)
  const query = useQuery({ queryKey: ['permission-catalog'], queryFn: ({ signal }) => requestJSON<{ permissions: Permission[] }>('/permissions', { signal }), retry: false })
  const rows = (query.data?.permissions || []).filter(p => (!sensitive || p.sensitive) && `${p.code} ${p.description}`.toLowerCase().includes(search.toLowerCase()))
  return <><PageHeader eyebrow="System / Access control" title="Permission catalog" description="The shared access rules for every protected operation. Assign staff access from Users & access." /><FilterBar onReset={search || sensitive ? () => { setSearch(''); setSensitive(false) } : undefined} summary={`${rows.length} permissions`}><SearchInput value={search} onValueChange={setSearch} label="Search permissions" /><label className="flex items-center gap-2 text-xs"><input type="checkbox" className="accent-primary" checked={sensitive} onChange={e => setSensitive(e.target.checked)} />Sensitive only</label></FilterBar><DataTable key={`${search}:${sensitive}`} caption="Permission catalog" rowKey={p => p.code} rows={rows} loading={query.isPending} error={query.error?.message} onRetry={() => void query.refetch()} columns={[{ id: 'code', header: 'Permission', compare: (a, b) => a.code.localeCompare(b.code), cell: p => <span className="font-mono text-xs">{p.code}</span> }, { id: 'description', header: 'Purpose', cell: p => <span className="block min-w-48 text-xs leading-5">{p.description}</span> }, { id: 'sensitive', header: 'Access level', cell: p => <StatusBadge tone={p.sensitive ? 'warning' : 'neutral'}>{p.sensitive ? 'Sensitive' : 'Standard'}</StatusBadge> }]} /></>
}
