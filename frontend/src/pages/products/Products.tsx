import { CostHistory } from '@/components/costs/cost-history'
import { Select, SelectItem } from '@/components/ui/select'
import { useState } from 'react'
import { useQuery, useMutation } from '@tanstack/react-query'
import { Plus, Pencil, Archive } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PageHeader, DataTable, FilterBar, SearchInput, StatusBadge, LoadingState, EmptyState, ConfirmDialog, PermissionGuard } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { permissions, type CurrentUser } from '@/permissions'
import { ProductForm } from './ProductForm'
import { conversion, decimalText, unitName, type Product, type Catalog } from './types'
export default function Products({ current }: { current: CurrentUser }) {
  const catalog = useQuery({ queryKey: ['catalog'], queryFn: ({ signal }) => requestJSON<Catalog>('/catalog', { signal }), retry: false })
  const path = window.location.pathname
  const id = path.split('/')[2]
  const product = useQuery({ queryKey: ['product', id], queryFn: ({ signal }) => requestJSON<Product>(`/products/${id}`, { signal }), enabled: !!id && id !== 'new', retry: false })
  if (catalog.isPending || (id && id !== 'new' && product.isPending)) return <LoadingState label="Loading product catalog…" />
  if (catalog.error || product.error) return <EmptyState title="Unable to load product" description={(catalog.error || product.error)?.message} action={<Button onClick={() => { void catalog.refetch(); if (id !== 'new') void product.refetch() }}>Try again</Button>} />
  if (!catalog.data) return null
  if (id === 'new') return <ProductForm catalog={catalog.data} current={current} />
  if (product.data && path.endsWith('/edit')) return product.data.archived_at ? <EmptyState title="This product is archived" action={<a href={`/products/${id}`}>View product details</a>} /> : <ProductForm key={id} product={product.data} catalog={catalog.data} current={current} />
  if (product.data) return <ProductDetails product={product.data} catalog={catalog.data} current={current} />
  return <ProductList catalog={catalog.data} current={current} />
}
function ProductList({ catalog, current }: { catalog: Catalog; current: CurrentUser }) {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('all')
  const [category, setCategory] = useState('')
  const [brand, setBrand] = useState('')
  const [page, setPage] = useState(1)
  const [size, setSize] = useState(20)
  const params = new URLSearchParams({ q: search, status, category_id: category, brand_id: brand, page: String(page), page_size: String(size) })
  const query = useQuery({ queryKey: ['products', params.toString()], queryFn: ({ signal }) => requestJSON<{ products: Product[]; total: number }>(`/products?${params}`, { signal }), retry: false })
  function reset() { setSearch(''); setStatus('all'); setCategory(''); setBrand(''); setPage(1) }
  return <><PageHeader eyebrow="Product & stock" title="Products" description="Your product catalog, packaging and stock thresholds." actions={<><PermissionGuard user={current} permission={permissions.catalogManage}><Button variant="outline" asChild><a href="/catalog">Manage catalog</a></Button></PermissionGuard><PermissionGuard user={current} permission={permissions.productsCreate}><Button asChild><a href="/products/new"><Plus />Add Product</a></Button></PermissionGuard></>} />
    <FilterBar onReset={search || category || brand || status !== 'all' ? reset : undefined} summary={query.data ? `${query.data.total} products` : undefined}><SearchInput label="Search products" placeholder="Name, SKU or barcode…" value={search} onValueChange={v => { setSearch(v); setPage(1) }} /><label className="flex items-center gap-2 text-xs">Status<Select aria-label="Status" className="w-auto" value={status} onValueChange={value => { setStatus(value); setPage(1) }}><SelectItem value="all">All current</SelectItem><SelectItem value="active">Active</SelectItem><SelectItem value="inactive">Inactive</SelectItem><SelectItem value="archived">Archived</SelectItem></Select></label>{(['categories', 'brands'] as const).map(kind => <label key={kind} className="flex items-center gap-2 text-xs">{kind === 'categories' ? 'Category' : 'Brand'}<Select aria-label={kind === 'categories' ? 'Category' : 'Brand'} className="w-40 max-w-44" value={kind === 'categories' ? category : brand} onValueChange={value => { (kind === 'categories' ? setCategory : setBrand)(value); setPage(1) }}><SelectItem value="">All</SelectItem>{catalog[kind].map(v => <SelectItem key={v.id} value={v.id}>{v.name}</SelectItem>)}</Select></label>)}</FilterBar>
    <DataTable caption="Products" rows={query.data?.products || []} rowKey={p => p.id} loading={query.isPending} error={query.error?.message} onRetry={() => void query.refetch()} pagination={{ page, pageSize: size, total: query.data?.total || 0, onPageChange: setPage }} columns={[
      { id: 'name', header: 'Product / SKU', cell: p => <div className="min-w-40"><a className="font-medium hover:text-primary hover:underline" href={`/products/${p.id}`}>{p.name}</a><p className="mt-1 font-mono text-xs text-muted-foreground">{p.sku}</p></div> },
      { id: 'category', header: 'Category / Brand', cell: p => <div className="min-w-28 text-xs"><p>{p.category_name || 'Uncategorized'}</p><p className="mt-1 text-muted-foreground">{p.brand_name || 'No brand'}</p></div> },
      { id: 'pack', header: 'Purchase packaging', cell: p => { const pack = p.packaging.find(u => u.is_default_purchase); return <span className="block min-w-40 text-xs">{pack ? conversion(pack, p.base_unit_code, catalog) : 'Not set'}</span> } },
      { id: 'min', header: 'Minimum stock', align: 'right', cell: p => <span className="whitespace-nowrap text-xs">{p.minimum_stock === null ? 'Not set' : `${decimalText(p.minimum_stock)} ${unitName(catalog, p.base_unit_code)}`}</span> },
      { id: 'status', header: 'Status', cell: p => <ProductStatus product={p} /> },
      { id: 'actions', header: 'Details', align: 'right', cell: p => <Button variant="ghost" size="sm" asChild><a href={`/products/${p.id}`} aria-label={`View ${p.sku}`}>View</a></Button> },
    ]} empty={<EmptyState title="No matching products" description="Add your first product or adjust the search and filters." action={page > 1 ? <Button onClick={() => setPage(1)}>Back to first page</Button> : undefined} />} />
    <label className="mt-4 flex items-center justify-end gap-2 text-xs text-muted-foreground">Rows per page<Select aria-label="Rows per page" className="w-auto" value={size} onValueChange={value => { setSize(Number(value)); setPage(1) }}>{[10,20,50,100].map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}</Select></label>
  </>
}
function ProductStatus({ product }: { product: Product }) { return <StatusBadge tone={product.archived_at ? 'neutral' : product.is_active ? 'success' : 'warning'}>{product.archived_at ? 'Archived' : product.is_active ? 'Active' : 'Inactive'}</StatusBadge> }
function ProductDetails({ product: p, catalog, current }: { product: Product; catalog: Catalog; current: CurrentUser }) {
  const [confirm, setConfirm] = useState(false)
  const archive = useMutation({ mutationFn: () => requestJSON(`/products/${p.id}`, { method: 'DELETE', body: JSON.stringify({ version: p.version }) }), onSuccess: () => window.location.assign('/products') })
  return <><PageHeader eyebrow="Product & stock / Product details" title={p.name} description={`SKU · ${p.sku}`} actions={<><Button variant="outline" asChild><a href="/products">All products</a></Button>{!p.archived_at && <><PermissionGuard user={current} permission={permissions.productsUpdate}><Button asChild><a href={`/products/${p.id}/edit`}><Pencil />Edit Product</a></Button></PermissionGuard><PermissionGuard user={current} permission={permissions.productsDelete}><Button variant="outline" onClick={() => setConfirm(true)}><Archive />Archive product</Button></PermissionGuard></>}</>} /><div className="mb-5"><ProductStatus product={p} /></div>
    <div className="grid gap-5 lg:grid-cols-[1.3fr_1fr]"><section className="panel p-5"><h2 className="mb-5 text-sm font-semibold">Product identity</h2><dl className="grid gap-5 sm:grid-cols-2">{[['Product barcode',p.barcode],['Category',p.category_name],['Brand',p.brand_name],['Country of origin',p.country_code],['Base stock unit',unitName(catalog,p.base_unit_code)],['Expiry tracking',p.tracks_expiry?'Enabled':'Disabled']].map(([label,value]) => <div key={label}><dt className="text-xs text-muted-foreground">{label}</dt><dd className="mt-2 break-words text-sm font-medium">{value || 'Not set'}</dd></div>)}</dl>{p.description && <p className="mt-6 whitespace-pre-wrap border-t pt-5 text-sm leading-6">{p.description}</p>}</section><section className="panel p-5"><h2 className="text-sm font-semibold">Stock threshold</h2><p className="mt-4 break-words text-2xl font-semibold tabular-nums">{p.minimum_stock === null ? 'Not set' : decimalText(p.minimum_stock)}</p><p className="mt-2 text-xs text-muted-foreground">Minimum stock · {unitName(catalog,p.base_unit_code)}</p><p className="mt-5 border-t pt-4 text-xs leading-5 text-muted-foreground">Stock is tracked by batch and warehouse through receiving and recorded movements.</p><PermissionGuard user={current} permission={permissions.inventoryView}><Button asChild variant="outline" className="mt-3"><a href={`/inventory?q=${encodeURIComponent(p.sku)}`}>View batch stock</a></Button></PermissionGuard></section></div>
    <section className="mt-6"><h2 className="mb-4 text-sm font-semibold">Packaging & conversions</h2><DataTable caption="Product packaging" rows={p.packaging} rowKey={v => v.unit_code} columns={[{id:'conversion',header:'Conversion',cell:v=><span className="whitespace-nowrap font-medium">{conversion(v,p.base_unit_code,catalog)}</span>},{id:'barcode',header:'Barcode',cell:v=><span className="font-mono text-xs">{v.barcode || 'Not set'}</span>},{id:'defaults',header:'Used for',cell:v=><div className="flex gap-2">{v.is_default_purchase&&<StatusBadge>Purchase</StatusBadge>}{v.is_default_sale&&<StatusBadge>Sale</StatusBadge>}</div>}]} /></section>
    <PermissionGuard user={current} permission={permissions.financeViewLandedCost}><CostHistory kind="products" id={p.id} current={current}/></PermissionGuard><p className="mt-5 text-xs text-muted-foreground">Created {new Date(p.created_at).toLocaleString()} · Updated {new Date(p.updated_at).toLocaleString()}</p><ConfirmDialog open={confirm} onOpenChange={setConfirm} title="Archive this product?" description={`${p.name} will be removed from the current catalog. Its SKU, barcodes and history remain reserved.`} confirmLabel="Archive product" destructive onConfirm={() => archive.mutate()} busy={archive.isPending} error={archive.error?.message} />
  </>
}
