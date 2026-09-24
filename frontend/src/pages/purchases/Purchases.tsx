import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { PageHeader, DataTable, FilterBar, SearchInput, StatusBadge, LoadingState, EmptyState } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import PurchaseForm from './PurchaseForm'
import { amount, type Purchase, type Currency } from './types'
export default function Purchases({ current }: { current: CurrentUser }) {
 const id = window.location.pathname.split('/')[2]
 const query = useQuery({ queryKey: ['purchase', id], queryFn: ({ signal }) => requestJSON<Purchase>(`/purchases/${id}`, { signal }), enabled: !!id && id !== 'new', retry: false })
 if (id === 'new') return <PurchaseForm current={current} />
 if (!id) return <PurchaseList current={current} />
 if (query.isPending) return <LoadingState label="Loading purchase…" />
 if (query.error) return <EmptyState title="Unable to load purchase" description={query.error.message} action={<Button onClick={() => void query.refetch()}>Try again</Button>} />
 return <PurchaseDetails p={query.data} current={current} />
}
function PurchaseList({ current }: { current: CurrentUser }) {
 const [search, setSearch] = useState('')
 const [currency, setCurrency] = useState('')
 const [status, setStatus] = useState('')
 const [page, setPage] = useState(1)
 const currencies = useQuery({ queryKey: ['currencies'], queryFn: ({ signal }) => requestJSON<Currency[]>('/currencies', { signal }) })
 const params = new URLSearchParams({ q: search, currency, status, page: String(page), page_size: '20' })
 const query = useQuery({ queryKey: ['purchases', params.toString()], queryFn: ({ signal }) => requestJSON<{ purchases: Purchase[]; total: number }>(`/purchases?${params}`, { signal }), retry: false })
 return <><PageHeader eyebrow="Purchasing / Transactions" title="Purchases" description="Supplier purchases with their original currency and historical MMK cost." actions={<>{can(current, permissions.exchangeRatesManage) && <Button variant="outline" asChild><a href="/purchasing-settings">Currencies & rates</a></Button>}{can(current, permissions.purchasesCreate) && can(current, permissions.purchasesViewCost) && <Button asChild><a href="/purchases/new"><Plus />Create Purchase</a></Button>}</>} />
  <FilterBar summary={query.data ? `${query.data.total} purchases` : undefined} onReset={search || currency || status ? () => { setSearch(''); setCurrency(''); setStatus(''); setPage(1) } : undefined}>
   <SearchInput label="Search purchases" placeholder="Purchase, invoice or supplier…" value={search} onValueChange={v => { setSearch(v); setPage(1) }} />
   <label className="flex items-center gap-2 text-xs">Currency<Select aria-label="Currency filter" className="w-auto" value={currency} onValueChange={v => { setCurrency(v); setPage(1) }}><SelectItem value="">All currencies</SelectItem>{(currencies.data || []).map(c => <SelectItem key={c.code} value={c.code}>{c.code}</SelectItem>)}</Select></label>
   <label className="flex items-center gap-2 text-xs">Status<Select aria-label="Status" className="w-auto" value={status} onValueChange={v => { setStatus(v); setPage(1) }}><SelectItem value="">All statuses</SelectItem>{['DRAFT','POSTED','CANCELLED','REVERSED'].map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</Select></label>
  </FilterBar>
  <DataTable caption="Purchases" rows={query.data?.purchases || []} rowKey={p => p.id} loading={query.isPending} error={query.error?.message} onRetry={() => void query.refetch()} pagination={{ page, pageSize: 20, total: query.data?.total || 0, onPageChange: setPage }} columns={[
   { id: 'number', header: 'Purchase / Date', cell: p => <div className="min-w-36"><a className="font-medium text-primary hover:underline" href={`/purchases/${p.id}`}>{p.purchase_number}</a><p className="mt-1 text-xs text-muted-foreground">{new Date(p.purchased_at).toLocaleDateString()}</p></div> },
   { id: 'supplier', header: 'Supplier / Invoice', cell: p => <div className="min-w-36"><p className="text-sm">{p.supplier_name}</p><p className="mt-1 text-xs text-muted-foreground">{p.supplier_invoice_number || 'No invoice'}</p></div> },
   { id: 'total', header: 'Original / MMK', align: 'right', cell: p => p.can_view_cost ? <div className="whitespace-nowrap text-xs tabular-nums"><p className="font-medium">{amount(p.total_original)} {p.currency_code}</p><p className="mt-1 text-muted-foreground">{amount(p.total_mmk)} MMK</p></div> : <span className="text-xs text-muted-foreground">Cost restricted · {p.currency_code}</span> },
   { id: 'status', header: 'Status', cell: p => <StatusBadge tone={p.status === 'POSTED' ? 'success' : 'neutral'}>{p.status}</StatusBadge> },
   { id: 'payment', header: 'Payment', cell: p => <span className="whitespace-nowrap text-xs">{p.can_view_cost ? p.payment_status?.replaceAll('_',' ') || 'Not posted' : 'Restricted'}</span> },
  ]} empty={<EmptyState title="No matching purchases" description="Create a purchase or adjust your filters." />} />
 </>
}
function PurchaseDetails({ p, current }: { p: Purchase; current: CurrentUser }) {
 return <><PageHeader eyebrow="Purchasing / Purchase details" title={p.purchase_number} description={`${p.supplier_name} · ${new Date(p.purchased_at).toLocaleDateString()}`} actions={<Button asChild variant="outline"><a href="/purchases">All purchases</a></Button>} />
  <div className="mb-5"><StatusBadge tone={p.status === 'POSTED' ? 'success' : 'neutral'}>{p.status}</StatusBadge></div>
  <div className="grid gap-5 lg:grid-cols-2"><section className="panel p-5"><h2 className="mb-4 text-sm font-semibold">Supplier & invoice</h2><dl className="grid gap-5 sm:grid-cols-2"><div><dt className="text-xs text-muted-foreground">Supplier</dt><dd className="mt-2 text-sm">{can(current, permissions.suppliersView) ? <a className="text-primary hover:underline" href={`/suppliers/${p.supplier_id}`}>{p.supplier_name}</a> : p.supplier_name}</dd></div>{[['Invoice',p.supplier_invoice_number],['Payment due',p.due_date],['Currency',p.currency_code]].map(([label,value]) => <div key={label}><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-2 text-sm">{value || 'Not set'}</dd></div>)}</dl>{p.notes && <p className="mt-5 whitespace-pre-wrap break-words border-t pt-4 text-sm">{p.notes}</p>}</section>
  <section className="panel p-5"><h2 className="text-sm font-semibold">Historical purchase cost</h2>{p.can_view_cost ? <><p data-testid="purchase-original" className="mt-4 text-2xl font-semibold tabular-nums">{amount(p.total_original)} {p.currency_code}</p><p data-testid="purchase-mmk" className="mt-2 text-xl font-semibold tabular-nums text-primary">{amount(p.total_mmk)} MMK</p><p className="mt-3 text-xs text-muted-foreground">1 {p.currency_code} = {amount(p.mmk_per_unit)} MMK · {p.exchange_rate_id ? 'Saved historical quote' : p.currency_code === 'MMK' ? 'Base currency' : 'Authorized transaction rate'}</p><p className="mt-4 border-t pt-4 text-xs text-muted-foreground">Posted rates and amounts are locked. This is the purchase cost before transport and landed-cost allocation.</p></> : <p className="mt-4 text-sm text-muted-foreground">Purchase costs require purchases.view_cost.</p>}</section></div>
  <h2 className="mb-4 mt-6 text-sm font-semibold">Purchase items</h2><DataTable caption="Purchase items" rows={p.items || []} rowKey={i => i.id} columns={[
   { id: 'product', header: 'Product / SKU', cell: i => <div className="min-w-36"><p className="font-medium">{i.product_name}</p><p className="mt-1 text-xs text-muted-foreground">{i.sku}</p></div> },
   { id: 'qty', header: 'Quantity / Conversion', cell: i => <div className="min-w-40 text-xs"><p>{amount(i.quantity)} {i.unit_name}</p><p className="mt-1 text-muted-foreground">× {amount(i.units_per_pack)} = {amount(i.base_quantity)} base units</p></div> },
   ...(p.can_view_cost ? [
    { id: 'price', header: 'Unit price', cell: (i: NonNullable<Purchase['items']>[number]) => <span className="whitespace-nowrap text-xs">{amount(i.unit_price_original)} {p.currency_code}</span> },
    { id: 'adjustments', header: 'Discount / Tax', cell: (i: NonNullable<Purchase['items']>[number]) => <span className="whitespace-nowrap text-xs">{amount(i.discount_original)} / {amount(i.tax_original)}</span> },
    { id: 'total', header: 'Line total', cell: (i: NonNullable<Purchase['items']>[number]) => <span className="whitespace-nowrap text-xs font-medium">{amount(i.total_original)} {p.currency_code}</span> },
   ] : []),
  ]} />
  {p.can_view_cost && <section className="panel mt-6 p-5"><h2 className="mb-4 text-sm font-semibold">Supplier payable for this purchase</h2><div className="grid gap-5 sm:grid-cols-3">{[['Payment status',p.payment_status?.replaceAll('_',' ') || 'Not posted'],['Paid (MMK)',`${amount(p.amount_paid_mmk)} MMK`],['Outstanding',`${amount(p.outstanding_original)} ${p.currency_code} / ${amount(p.outstanding_mmk)} MMK`]].map(([label,value]) => <div key={label}><p className="text-xs text-muted-foreground">{label}</p><p className="mt-2 text-sm font-medium tabular-nums">{value}</p></div>)}</div></section>}
 </>
}
