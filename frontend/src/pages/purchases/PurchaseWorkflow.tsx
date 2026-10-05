import { amount, quantityDifference, packageQuantity } from './types'
import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, Clock, PackageCheck, Truck } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { EmptyState, LoadingState, Modal, StatusBadge } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import CreateShipment from '../shipments/CreateShipment'
import { ShipmentDetails } from '../shipments/Shipments'
import type { Choice, Shipment } from '../shipments/types'
import type { Purchase } from './types'

type LinkedShipment = Shipment & { receipt_id:string|null; receipt_number:string|null }
export type Workflow = { choices:(Choice & {base_quantity:string;units_per_pack:string;unit_code:string;quantity:string})[]; shipments:LinkedShipment[] }
const positive = (v:string) => /^\d+(\.\d+)?$/.test(v) && BigInt(v.replace('.', '')) > 0n

export default function PurchaseWorkflow({purchase:p,current}:{purchase:Purchase;current:CurrentUser}) {
 const client=useQueryClient()
 const [reversing,setReversing]=useState(false)
 const [reason,setReason]=useState('')
 const reverse=useMutation({mutationFn:()=>requestJSON(`/purchases/${p.id}/reverse`,{method:'POST',body:JSON.stringify({reason})}),onSuccess:async()=>{await client.invalidateQueries({queryKey:['purchase',p.id]});await client.invalidateQueries({queryKey:['purchase-workflow',p.id]});setReversing(false)}})
 const [adding,setAdding]=useState(false)
 const [selected,setSelected]=useState('')
 const allowed=can(current,permissions.shipmentsView)
 const query=useQuery({queryKey:['purchase-workflow',p.id],queryFn:({signal})=>requestJSON<Workflow>(`/purchases/${p.id}/workflow`,{signal}),enabled:allowed,retry:false})
 if(!allowed)return <section className="panel mb-6 p-5"><h2 className="text-sm font-semibold">Purchase progress</h2><p className="mt-2 text-sm text-muted-foreground">Transportation and receiving details require shipment viewing permission.</p></section>
 if(query.isPending)return <LoadingState label="Loading purchase progress…"/>
 if(query.error)return <EmptyState title="Unable to load purchase progress" description={query.error.message} action={<Button onClick={()=>void query.refetch()}>Retry</Button>}/>
 const w=query.data
 const active=w.shipments.filter(s=>s.status!=='CANCELLED')
 const remaining=w.choices.filter(c=>positive(c.available_quantity))
 const allAllocated=w.choices.length>0&&remaining.length===0
 const completed=allAllocated&&active.length>0&&active.every(s=>s.status==='RECEIVED'&&s.receipt_id)
 const shipped=allAllocated&&active.length>0&&active.every(s=>['IN_TRANSIT','ARRIVED','RECEIVED'].includes(s.status))
 const costed=allAllocated&&active.length>0&&active.every(s=>s.costs_finalized_at)
 const steps=[['Purchase & supplier',p.status==='POSTED'],['Transportation / shipment',allAllocated],['Landed costs',costed],['Goods in transit',shipped],['Goods received',completed],['Inventory updated',completed]] as const
 const chosen=w.shipments.find(s=>s.id===selected)||active.find(s=>s.status!=='RECEIVED')||active[0]||w.shipments[0]
 return <section aria-label="Purchase workflow" className="mb-6 min-w-0 space-y-5">
  <div className="panel space-y-5 p-5"><div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="text-lg font-semibold">Purchase progress</h2><p className="mt-1 text-sm text-muted-foreground">{p.status==='REVERSED'?'Reversed · original purchase preserved in history':completed?'Completed · goods received and inventory updated':remaining.length?'Continue with transportation whenever the details are ready.':'Continue the shipment below to costing and goods receiving.'}</p></div><StatusBadge tone={completed?'success':'warning'}>{p.status==='REVERSED'?'Reversed':completed?'Completed':'In progress'}</StatusBadge></div>
   <ol className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{steps.map(([name,done])=><li key={name} className={`flex items-center gap-3 rounded-xl border p-3 ${done?'bg-green-50/50':'bg-muted/30'}`}>{done?<Check className="size-4 shrink-0 text-green-700"/>:<Clock className="size-4 shrink-0 text-amber-600"/>}<div><p className="text-xs font-medium">{name}</p><p className="mt-1 text-xs text-muted-foreground">{done?'Completed':'Pending'}</p></div></li>)}</ol>
   {remaining.length>0&&p.status==='POSTED'&&<div className="flex flex-wrap items-center justify-between gap-3 border-t pt-4"><p className="text-sm text-muted-foreground">{remaining.length} purchase item{remaining.length===1?'':'s'} still have unshipped quantities.</p>{can(current,permissions.shipmentsManage)&&<Button onClick={()=>setAdding(true)}><Truck/>Arrange shipment</Button>}</div>}
  </div>
  <div className="panel overflow-x-auto p-5"><h3 className="mb-3 text-sm font-semibold">Shipment allocation</h3><table className="w-full text-left text-sm"><thead><tr>{['Product','Purchased','Assigned','Remaining'].map(h=><th className="p-2" key={h}>{h}</th>)}</tr></thead><tbody>{w.choices.map(c=><tr key={c.id} className="border-t"><td className="p-2">{c.product_name}</td><td className="p-2">{amount(c.quantity)} {c.unit_code}</td><td className="p-2">{amount(packageQuantity(quantityDifference(c.base_quantity,c.available_quantity),c.units_per_pack))} {c.unit_code}</td><td className="p-2">{amount(packageQuantity(c.available_quantity,c.units_per_pack))} {c.unit_code}<p className="text-xs text-muted-foreground">{amount(c.available_quantity)} base units</p></td></tr>)}</tbody></table></div>
  {w.shipments.length>0&&<><div className="flex flex-wrap gap-2" aria-label="Linked shipments">{w.shipments.map(s=><Button key={s.id} variant={chosen?.id===s.id?'default':'outline'} onClick={()=>setSelected(s.id)}>{s.shipment_number} · {s.status.replaceAll('_',' ')}</Button>)}</div>{chosen&&<div className="min-w-0 rounded-2xl border bg-white p-4 sm:p-5"><ShipmentDetails key={chosen.id} id={chosen.id} current={current} embedded/>{chosen.receipt_id&&<div className="mt-5 flex flex-wrap items-center gap-3 rounded-xl bg-green-50 p-4 text-sm"><PackageCheck className="size-5 text-green-700"/><span>Goods received · {chosen.receipt_number} · inventory updated</span>{can(current,permissions.receivingManage)&&<Button asChild variant="outline" size="sm"><a href={`/receiving/${chosen.receipt_id}`}>View receipt history</a></Button>}</div>}</div>}</>}
  {p.status==='POSTED'&&active.length===0&&can(current,permissions.transactionsReverse)&&<div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border p-4"><p className="text-xs text-muted-foreground">Posted purchase amounts are preserved. Reverse an unshipped, unpaid purchase to correct it; downstream activity requires linked corrections.</p><Button variant="outline" onClick={()=>setReversing(true)}>Reverse purchase</Button></div>}
  <Modal open={reversing} onOpenChange={setReversing} title="Reverse purchase"><form className="space-y-4" onSubmit={e=>{e.preventDefault();reverse.mutate()}}><p className="text-sm">The original record stays in history. Purchases with shipment, payment or return activity cannot be reversed here.</p><label className="block text-sm">Reversal reason<input required maxLength={1000} className="field mt-2" value={reason} onChange={e=>setReason(e.target.value)}/></label>{reverse.error&&<p role="alert" className="text-sm text-destructive">{reverse.error.message}</p>}<Button disabled={reverse.isPending}>Confirm reversal</Button></form></Modal>
  <Modal open={adding} onOpenChange={setAdding} title={`Arrange shipment · ${p.purchase_number}`}>{adding&&<CreateShipment current={current} purchaseID={p.id} choices={remaining} done={async id=>{await client.invalidateQueries({queryKey:['purchase-workflow',p.id]});setSelected(id);setAdding(false)}}/>}</Modal>
 </section>
}
