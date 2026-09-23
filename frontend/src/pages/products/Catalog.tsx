import { useState, type FormEvent } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { PageHeader, DataTable, StatusBadge, Modal, FormField } from '@/components/shared'
import { requestJSON } from '@/services/api'
import type { Catalog, Lookup } from './types'
type Kind = 'categories' | 'brands' | 'units'
export default function CatalogPage() {
  const client = useQueryClient()
  const query = useQuery({ queryKey: ['catalog'], queryFn: ({ signal }) => requestJSON<Catalog>('/catalog', { signal }), retry: false })
  const [kind, setKind] = useState<Kind>('categories')
  const [editing, setEditing] = useState<Lookup | 'new' | null>(null)
  const [name, setName] = useState('')
  const [code, setCode] = useState('')
  const [active, setActive] = useState(true)
  const save = useMutation({ mutationFn: () => requestJSON(`/catalog/${kind}${editing && editing !== 'new' ? `/${editing.id}` : ''}`, { method: editing === 'new' ? 'POST' : 'PUT', body: JSON.stringify(kind === 'units' ? { code, name } : { name, is_active: active }) }), onSuccess: async () => { await client.invalidateQueries({ queryKey: ['catalog'] }); setEditing(null) } })
  function edit(row: Lookup | 'new') { save.reset(); setEditing(row); setName(row === 'new' ? '' : row.name); setCode(''); setActive(row === 'new' ? true : row.is_active) }
  function submit(e: FormEvent) { e.preventDefault(); if (!save.isPending) save.mutate() }
  const singular = kind === 'categories' ? 'category' : kind === 'brands' ? 'brand' : 'unit'
  return <><PageHeader eyebrow="Product & stock / Reference data" title="Catalog setup" description="Organize products with shared categories, brands and packaging units." actions={<Button variant="outline" asChild><a href="/products">Products</a></Button>} /><div className="mb-5 flex flex-wrap items-center justify-between gap-4"><div className="flex gap-1 rounded-lg border bg-white p-1" role="group" aria-label="Catalog type">{(['categories','brands','units'] as const).map(v => <Button key={v} variant={kind === v ? 'secondary' : 'ghost'} aria-pressed={kind === v} onClick={() => setKind(v)}>{v === 'categories' ? 'Categories' : v === 'brands' ? 'Brands' : 'Units'}</Button>)}</div><Button onClick={() => edit('new')}>Add {singular}</Button></div>
    {kind === 'units' ? <DataTable caption="Packaging unit definitions" rows={query.data?.units || []} rowKey={r => r.code} loading={query.isPending} error={query.error?.message} onRetry={() => void query.refetch()} columns={[{ id:'code',header:'Code',cell:r=><span className="font-mono text-xs">{r.code}</span> },{id:'name',header:'Name',cell:r=>r.name}]} /> : <DataTable key={kind} caption={kind === 'categories' ? 'Categories' : 'Brands'} rows={query.data?.[kind] || []} rowKey={r => r.id} loading={query.isPending} error={query.error?.message} onRetry={() => void query.refetch()} columns={[{id:'name',header:'Name',compare:(a,b)=>a.name.localeCompare(b.name),cell:r=><span className="font-medium">{r.name}</span>},{id:'status',header:'Status',cell:r=><StatusBadge tone={r.is_active?'success':'neutral'}>{r.is_active?'Active':'Inactive'}</StatusBadge>},{id:'edit',header:'Actions',align:'right',cell:r=><Button variant="outline" size="sm" onClick={()=>edit(r)} aria-label={`Edit ${r.name}`}>Edit</Button>}]} />}
    <p className="mt-4 text-xs leading-5 text-muted-foreground">Inactive categories and brands remain linked to existing products. Unit codes are permanent; conversions are configured per product.</p>
    <Modal open={editing !== null} onOpenChange={open => { if (!open) setEditing(null) }} title={`${editing === 'new' ? 'Add' : 'Edit'} ${singular}`} description="Changes apply to the shared product catalog." busy={save.isPending} footer={<><Button variant="outline" disabled={save.isPending} onClick={() => setEditing(null)}>Cancel</Button><Button type="submit" form="catalog-form" disabled={save.isPending}>{save.isPending?'Saving…':'Save'}</Button></>}><form id="catalog-form" onSubmit={submit} className="space-y-4"><FormField label="Name" required>{p=><input {...p} className="field" value={name} onChange={e=>setName(e.target.value)} maxLength={100}/>}</FormField>{kind==='units'&&<FormField label="Unit code" required hint="Up to 20 uppercase letters, digits and underscores.">{p=><input {...p} className="field uppercase" value={code} onChange={e=>setCode(e.target.value.toUpperCase())} maxLength={20}/>}</FormField>}{editing!=='new'&&kind!=='units'&&<label className="flex gap-2 text-sm"><input type="checkbox" className="accent-primary" checked={active} onChange={e=>setActive(e.target.checked)}/>Active</label>}{save.error&&<p role="alert" className="text-sm text-destructive">{save.error.message}</p>}</form></Modal>
  </>
}
