import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { PageHeader, SearchInput, DataTable } from '@/components/shared'
import { Select, SelectItem } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { requestJSON } from '@/services/api'
import { amount } from '../purchases/types'
import { PriceEditor } from './Editors'
import type { Product } from './cart'
export default function WarehousePrices(){
 const [warehouse,setWarehouse]=useState(''),[search,setSearch]=useState(''),[edit,setEdit]=useState<Product|null>(null)
 const warehouses=useQuery({queryKey:['pos-warehouses'],queryFn:()=>requestJSON<{id:string;name:string}[]>('/pos/warehouses')})
 const active=warehouse||warehouses.data?.[0]?.id||''
 const products=useQuery({queryKey:['pos-products',active,search],queryFn:()=>requestJSON<Product[]>(`/pos/products?warehouse_id=${active}&q=${encodeURIComponent(search)}`),enabled:!!active})
 return <><PageHeader title="Warehouse prices" eyebrow="Products & stock / Pricing" description="Set carton and individual-unit selling prices after finalizing purchase, cargo and additional costs. Each warehouse has its own prices. Select a finalized shipment as the cost reference; customer special prices still take priority."/><div className="mb-5 flex flex-wrap gap-3"><Select aria-label="Pricing warehouse" value={active} onValueChange={setWarehouse}>{warehouses.data?.map(w=><SelectItem key={w.id} value={w.id}>{w.name}</SelectItem>)}</Select><SearchInput label="Find pricing product" value={search} onValueChange={setSearch}/></div>{warehouses.error&&<p role="alert">{warehouses.error.message}</p>}<DataTable caption="Warehouse selling prices" rows={products.data||[]} rowKey={p=>p.id} loading={!!active&&products.isPending} error={products.error?.message} columns={[{id:'product',header:'Product',cell:p=>p.name},{id:'prices',header:'Unit · Retail / Wholesale (MMK)',cell:p=><div>{p.packaging.map(u=><p key={u.unit_code}>{u.unit_code}: {amount(u.retail_price_mmk)} / {amount(u.wholesale_price_mmk)}</p>)}</div>},{id:'edit',header:'Action',cell:p=><Button onClick={()=>setEdit(p)}>Set prices</Button>}]}/>{edit&&<PriceEditor key={active+edit.id} warehouse={active} product={edit} onClose={()=>setEdit(null)}/>}</>
}
