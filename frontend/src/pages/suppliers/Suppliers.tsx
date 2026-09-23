import { Select, SelectItem } from '@/components/ui/select'
import { useState } from 'react'
import { useQuery, useMutation } from '@tanstack/react-query'
import { Plus, Pencil, Archive } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PageHeader, DataTable, FilterBar, SearchInput, StatusBadge, LoadingState, EmptyState, ConfirmDialog, PermissionGuard } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import { SupplierForm } from './SupplierForm'
import type { Supplier, History } from './types'

export default function Suppliers({ current }: { current: CurrentUser }) {
  const path = window.location.pathname
  const id = path.split('/')[2]
  const query = useQuery({ queryKey: ['supplier', id], queryFn: ({ signal }) => requestJSON<Supplier>(`/suppliers/${id}`, { signal }), enabled: !!id && id !== 'new', retry: false })
  if (!id) return <SupplierList current={current} />
  if (id === 'new') return <SupplierForm />
  if (query.isPending) return <LoadingState label="Loading supplier…" />
  if (query.error) return <EmptyState title="Unable to load supplier" description={query.error.message} action={<Button onClick={() => void query.refetch()}>Try again</Button>} />
  if (path.endsWith('/edit')) return query.data.archived_at ? <EmptyState title="This supplier is archived" action={<a href={`/suppliers/${id}`}>View supplier details</a>} /> : <SupplierForm key={id} supplier={query.data} />
  return <SupplierDetails supplier={query.data} current={current} />
}
function SupplierStatus({ supplier: s }: { supplier: Supplier }) {
  return <StatusBadge tone={s.archived_at ? 'neutral' : s.is_active ? 'success' : 'warning'}>{s.archived_at ? 'Archived' : s.is_active ? 'Active' : 'Inactive'}</StatusBadge>
}
function SupplierList({ current }: { current: CurrentUser }) {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('all')
  const [country, setCountry] = useState('')
  const [page, setPage] = useState(1)
  const [size, setSize] = useState(20)
  const params = new URLSearchParams({ q: search, status, country: country.length === 2 ? country : '', page: String(page), page_size: String(size) })
  const query = useQuery({ queryKey: ['suppliers', params.toString()], queryFn: ({ signal }) => requestJSON<{ suppliers: Supplier[]; total: number }>(`/suppliers?${params}`, { signal }), retry: false })
  return <>
    <PageHeader eyebrow="Purchasing / Relationships" title="Suppliers" description="Your supply partners, contact details and trading terms." actions={<PermissionGuard user={current} permission={permissions.suppliersCreate}><Button asChild><a href="/suppliers/new"><Plus />Add Supplier</a></Button></PermissionGuard>} />
    <FilterBar summary={query.data ? `${query.data.total} suppliers` : undefined} onReset={search || country || status !== 'all' ? () => { setSearch(''); setCountry(''); setStatus('all'); setPage(1) } : undefined}>
      <SearchInput label="Search suppliers" placeholder="Name, code, contact or phone…" value={search} onValueChange={v => { setSearch(v); setPage(1) }} />
      <label className="flex items-center gap-2 text-xs">Status<Select aria-label="Status" className="w-auto" value={status} onValueChange={value => { setStatus(value); setPage(1) }}><SelectItem value="all">All current</SelectItem><SelectItem value="active">Active</SelectItem><SelectItem value="inactive">Inactive</SelectItem><SelectItem value="archived">Archived</SelectItem></Select></label>
      <label className="flex items-center gap-2 text-xs">Country<input aria-label="Country filter" className="field w-24 uppercase" placeholder="e.g. MM" maxLength={2} value={country} onChange={e => { setCountry(e.target.value.toUpperCase().replace(/[^A-Z]/g, '')); setPage(1) }} /></label>
    </FilterBar>
    <DataTable caption="Suppliers" rows={query.data?.suppliers || []} rowKey={s => s.id} loading={query.isPending} error={query.error?.message} onRetry={() => void query.refetch()} pagination={{ page, pageSize: size, total: query.data?.total || 0, onPageChange: setPage }} columns={[
      { id: 'supplier', header: 'Supplier / Code', cell: s => <div className="min-w-40"><a className="font-medium hover:text-primary hover:underline" href={`/suppliers/${s.id}`}>{s.name}</a><p className="mt-1 font-mono text-xs text-muted-foreground">{s.code}</p></div> },
      { id: 'contact', header: 'Contact', cell: s => <div className="min-w-32 text-xs"><p>{s.contact_person || 'Not set'}</p><p className="mt-1 text-muted-foreground">{s.phone || 'No phone'}</p></div> },
      { id: 'country', header: 'Country / Type', cell: s => <div className="min-w-24 text-xs"><p>{s.country_code || 'Not set'}</p><p className="mt-1 text-muted-foreground">{s.supplier_type || 'Not set'}</p></div> },
      { id: 'terms', header: 'Payment terms', cell: s => <span className="block min-w-32 max-w-64 truncate text-xs" title={s.payment_terms || ''}>{s.payment_terms || 'Not set'}</span> },
      { id: 'status', header: 'Status', cell: s => <SupplierStatus supplier={s} /> },
      { id: 'details', header: 'Details', cell: s => <Button variant="ghost" size="sm" asChild><a href={`/suppliers/${s.id}`} aria-label={`View ${s.code}`}>View</a></Button> },
    ]} empty={<EmptyState title="No matching suppliers" description="Add your first supplier or adjust the search and filters." action={page > 1 ? <Button onClick={() => setPage(1)}>Back to first page</Button> : undefined} />} />
    <label className="mt-4 flex items-center justify-end gap-2 text-xs text-muted-foreground">Rows per page<Select aria-label="Rows per page" className="w-auto" value={size} onValueChange={value => { setSize(Number(value)); setPage(1) }}>{[10,20,50,100].map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}</Select></label>
  </>
}
function SupplierDetails({ supplier: s, current }: { supplier: Supplier; current: CurrentUser }) {
  const [confirm, setConfirm] = useState(false)
  const archive = useMutation({ mutationFn: () => requestJSON(`/suppliers/${s.id}`, { method: 'DELETE', body: JSON.stringify({ version: s.version }) }), onSuccess: () => window.location.assign('/suppliers') })
  return <>
    <PageHeader eyebrow="Purchasing / Supplier details" title={s.name} description={`Supplier code · ${s.code}`} actions={<>
      <Button asChild variant="outline"><a href="/suppliers">All suppliers</a></Button>
      {!s.archived_at && <><PermissionGuard user={current} permission={permissions.suppliersUpdate}><Button asChild><a href={`/suppliers/${s.id}/edit`}><Pencil />Edit Supplier</a></Button></PermissionGuard><PermissionGuard user={current} permission={permissions.suppliersDelete}><Button variant="outline" onClick={() => setConfirm(true)}><Archive />Archive supplier</Button></PermissionGuard></>}
    </>} />
    <div className="mb-5"><SupplierStatus supplier={s} /></div>
    <div className="grid gap-5 lg:grid-cols-2">
      <section className="panel p-5"><h2 className="mb-5 text-sm font-semibold">Contact & location</h2><dl className="grid gap-5 sm:grid-cols-2">{[['Contact person', s.contact_person], ['Phone number', s.phone], ['Country', s.country_code], ['Supplier type', s.supplier_type]].map(([label, value]) => <div key={label}><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-2 break-words text-sm font-medium">{value || 'Not set'}</dd></div>)}</dl><h3 className="mb-2 mt-6 text-xs text-muted-foreground">Address</h3><p className="whitespace-pre-wrap break-words text-sm">{s.address || 'Not set'}</p></section>
      <section className="panel p-5"><h2 className="mb-3 text-sm font-semibold">Payment terms</h2><p className="whitespace-pre-wrap break-words text-sm leading-6">{s.payment_terms || 'No payment terms recorded.'}</p><h2 className="mb-3 mt-6 border-t pt-5 text-sm font-semibold">Notes</h2><p className="whitespace-pre-wrap break-words text-sm leading-6">{s.notes || 'No notes recorded.'}</p></section>
    </div>
    <section className="mt-6"><h2 className="mb-4 text-sm font-semibold">Purchase history</h2>{can(current, permissions.purchasesView) ? <PurchaseHistory id={s.id} /> : <EmptyState title="Purchase history restricted" description="Viewing supplier purchases requires the purchases.view permission." />}</section>
    <p className="mt-5 text-xs text-muted-foreground">Created {new Date(s.created_at).toLocaleString()} · Updated {new Date(s.updated_at).toLocaleString()}</p>
    <ConfirmDialog open={confirm} onOpenChange={setConfirm} title="Archive this supplier?" description={`${s.name} will leave the current supplier list. Its code and purchase history will be preserved.`} confirmLabel="Archive supplier" destructive onConfirm={() => archive.mutate()} busy={archive.isPending} error={archive.error?.message} />
  </>
}
function PurchaseHistory({ id }: { id: string }) {
  const [page, setPage] = useState(1)
  const query = useQuery({ queryKey: ['supplier-history', id, page], queryFn: ({ signal }) => requestJSON<History>(`/suppliers/${id}/purchases?page=${page}&page_size=10`, { signal }), retry: false })
  return <DataTable caption="Supplier purchases" rows={query.data?.purchases || []} rowKey={p => p.id} loading={query.isPending} error={query.error?.message} onRetry={() => void query.refetch()} pagination={{ page, pageSize: 10, total: query.data?.total || 0, onPageChange: setPage }} columns={[
    { id: 'number', header: 'Purchase / Invoice', cell: p => <div className="min-w-36"><p className="font-mono text-xs font-medium">{p.purchase_number}</p><p className="mt-1 text-xs text-muted-foreground">{p.supplier_invoice_number || 'No invoice number'}</p></div> },
    { id: 'date', header: 'Purchased', cell: p => <span className="whitespace-nowrap text-xs">{new Date(p.purchased_at).toLocaleDateString()}</span> },
    { id: 'due', header: 'Due date', cell: p => <span className="whitespace-nowrap text-xs">{p.due_date || 'Not set'}</span> },
    { id: 'items', header: 'Lines', align: 'right', cell: p => p.item_count },
    { id: 'status', header: 'Status', cell: p => <StatusBadge tone={p.status === 'POSTED' ? 'success' : 'neutral'}>{p.status}</StatusBadge> },
    ...(query.data?.can_view_cost ? [{ id: 'total', header: 'Purchase total', cell: (p: History['purchases'][number]) => <span className="whitespace-nowrap font-mono text-xs">{p.total_original} {p.currency_code}</span> }] : []),
  ]} empty={<EmptyState title="No purchases recorded" description="Purchases recorded for this supplier will appear here." />} />
}
