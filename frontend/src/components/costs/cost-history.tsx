import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { CostJourney,type PurchaseSource } from './cost-journey'
import { Button } from '@/components/ui/button'
import { Select,SelectItem } from '@/components/ui/select'
import { LoadingState,EmptyState } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { can,permissions,type CurrentUser } from '@/permissions'
import { amount } from '@/pages/purchases/types'
type Journey={id:string;product_name:string;shipment_id:string;shipment_number:string;purchase_mmk:string;transport_mmk:string;expense_mmk:string;landed_mmk:string;sellable_quantity:string;unit_cost_mmk:string|null;sources:PurchaseSource[]}
export function CostHistory({kind,id,current}:{kind:'products'|'purchases';id:string;current:CurrentUser}){
 const [page,setPage]=useState(1);const [selected,setSelected]=useState('')
 const q=useQuery({queryKey:['cost-journeys',kind,id,page],queryFn:({signal})=>requestJSON<{journeys:Journey[];total:number}>(`/${kind}/${id}/cost-journeys?page=${page}&page_size=10`,{signal}),retry:false})
 const row=q.data?.journeys.find(j=>j.id===selected)||q.data?.journeys[0]
 return <section className="mt-6 min-w-0 space-y-3"><h2 className="text-sm font-semibold">Historical cost journeys</h2>{q.isPending?<LoadingState/>:q.error?<div className="panel p-4"><p role="alert">{q.error.message}</p><Button onClick={()=>void q.refetch()}>Retry journeys</Button></div>:!row?<EmptyState title="No finalized cost journey yet" description="A journey appears when shipment costs for this item are finalized."/>:<><Select aria-label="Historical shipment cost" value={row.id} onValueChange={setSelected}>{q.data?.journeys.map(j=><SelectItem key={j.id} value={j.id}>{j.shipment_number} · {j.product_name} · {amount(j.sellable_quantity)} sellable units · {amount(j.landed_mmk)} MMK</SelectItem>)}</Select><CostJourney key={row.id} sources={row.sources} converted={row.purchase_mmk} transport={row.transport_mmk} other={row.expense_mmk} landed={row.landed_mmk} finalized scope={`${row.shipment_number} · selected item allocation · ${amount(row.sellable_quantity)} sellable units`} zeroSellable={row.unit_cost_mmk===null} canPreviewProfit={can(current,permissions.financeViewProfit)} notes={`Actual unit cost: ${row.unit_cost_mmk===null?'No sellable units':amount(row.unit_cost_mmk)+' MMK'}. Historical shipment allocation; no current batch stock implied.`}/><div className="flex flex-wrap items-center justify-between gap-2 text-xs">{can(current,permissions.shipmentsView)&&<a className="text-primary hover:underline" href={`/shipments/${row.shipment_id}`}>Open shipment</a>}<div className="flex items-center gap-2"><Button size="sm" variant="outline" disabled={page===1} onClick={()=>{setPage(page-1);setSelected('')}}>Previous journeys</Button><span>{page} / {Math.ceil((q.data?.total||0)/10)}</span><Button size="sm" variant="outline" disabled={page*10>=(q.data?.total||0)} onClick={()=>{setPage(page+1);setSelected('')}}>Next journeys</Button></div></div></>}</section>
}
