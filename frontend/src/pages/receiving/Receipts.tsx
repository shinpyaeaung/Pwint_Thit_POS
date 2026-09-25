import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { PageHeader,DataTable,SearchInput,FilterBar,StatusBadge,LoadingState,EmptyState } from '@/components/shared'
import { can,permissions,type CurrentUser } from '@/permissions'
import { requestJSON } from '@/services/api'
import { amount } from '../purchases/types'
import { dateLabel } from '../shipments/types'
import ReceiveForm from './ReceiveForm'
import type { Receipt } from './types'
export default function Receipts({current}:{current:CurrentUser}){const id=window.location.pathname.split('/')[2];return id==='new'?<ReceiveForm/>:id?<Details id={id} current={current}/>:<List/>}
function List(){
 const [q,setQ]=useState('');const [page,setPage]=useState(1)
 const query=useQuery({queryKey:['receiving',q,page],queryFn:({signal})=>requestJSON<{total:number;receipts:Receipt[]}>(`/receiving?q=${encodeURIComponent(q)}&page=${page}&page_size=20`,{signal})})
 return <><PageHeader eyebrow="Warehouse / Goods receiving" title="Goods receiving" description="Compare expected goods with physical counts, then post one complete receipt per shipment." actions={<Button asChild><a href="/receiving/new">Receive shipment</a></Button>}/><FilterBar><SearchInput label="Search receipts" value={q} onValueChange={v=>{setQ(v);setPage(1)}} placeholder="Receipt or shipment number…"/></FilterBar><DataTable caption="Goods receipts" rows={query.data?.receipts||[]} rowKey={r=>r.id} loading={query.isPending} error={query.error?.message} onRetry={()=>void query.refetch()} pagination={{page,pageSize:20,total:query.data?.total||0,onPageChange:setPage}} columns={[{id:'number',header:'Receipt',cell:r=><a className="font-medium text-primary" href={`/receiving/${r.id}`}>{r.receipt_number}</a>},{id:'shipment',header:'Shipment',cell:r=>r.shipment_number},{id:'warehouse',header:'Warehouse',cell:r=>r.warehouse_name},{id:'date',header:'Received',cell:r=>dateLabel(r.received_at)},{id:'status',header:'Status',cell:r=><StatusBadge tone="success">{r.status}</StatusBadge>}]}/></>
}
function Details({id,current}:{id:string;current:CurrentUser}){
 const q=useQuery({queryKey:['receiving',id],queryFn:()=>requestJSON<Receipt>(`/receiving/${id}`),retry:false})
 if(q.isPending)return <LoadingState/>
 if(q.error)return <EmptyState title="Unable to load receipt" description={q.error.message} action={<Button onClick={()=>void q.refetch()}>Retry</Button>}/>
 const r=q.data
 return <><PageHeader eyebrow="Warehouse / Posted receipt" title={r.receipt_number} description={`${r.shipment_number} · ${r.warehouse_name}`} actions={<><Button asChild variant="outline"><a href="/receiving">All receipts</a></Button>{can(current,permissions.inventoryView)&&<Button asChild><a href="/inventory">View inventory</a></Button>}</>}/><section className="panel mb-5 space-y-3 p-5"><StatusBadge tone="success">{r.status}</StatusBadge><p className="text-sm">Received {dateLabel(r.received_at)} · {r.received_by}</p>{r.notes&&<p className="text-sm">{r.notes}</p>}<p className="text-xs text-muted-foreground">Posted counts and batch costs are preserved. Corrections require a controlled stock adjustment.</p></section><DataTable caption="Received goods" rows={r.items} rowKey={i=>i.id} pageSize={100} columns={[{id:'product',header:'Product / Batch',cell:i=><div className="min-w-36">{i.product_name}<p className="text-xs text-muted-foreground">{i.batch_number} · {i.base_unit}</p>{i.expires_on&&<p className="text-xs">Expires {i.expires_on}</p>}{i.notes&&<p className="mt-1 text-xs">{i.notes}</p>}</div>},...(['expected_quantity','received_quantity','missing_quantity','damaged_quantity','sellable_quantity'] as const).map((key,index)=>({id:key,header:['Expected','Received','Missing','Damaged','Sellable'][index],cell:(i:Receipt['items'][number])=><span className="tabular-nums">{amount(i[key])}</span>}))]}/></>
}
