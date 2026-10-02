import { OptionalSection } from '@/components/shared/optional-section'
import { useState } from 'react'
import { useMutation,useQuery,useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { Select,SelectItem } from '@/components/ui/select'
import { PageHeader,SearchInput,LoadingState,EmptyState,FormField,QuantityInput,ConfirmDialog } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { Field } from '../shipments/Fields'
import { iso,localDate } from '../shipments/types'
import { amount } from '../purchases/types'
import { counts,type ReceivingShipment,type Count } from './types'
export default function ReceiveForm({shipmentID,done}:{shipmentID?:string;done?:()=>void}={}){
 const [id,setID]=useState(()=>shipmentID||new URLSearchParams(window.location.search).get('shipment')||'');const [search,setSearch]=useState('')
 const options=useQuery({queryKey:['receiving-options',search],queryFn:({signal})=>requestJSON<{id:string;shipment_number:string;warehouse_name:string}[]>(`/receiving/options?q=${encodeURIComponent(search)}`,{signal})})
 const q=useQuery({queryKey:['receiving-shipment',id],queryFn:()=>requestJSON<ReceivingShipment>(`/receiving/shipments/${id}`),enabled:!!id,retry:false})
 return <>{!shipmentID && <><PageHeader eyebrow="Warehouse / Receive goods" title="Receive shipment" description="Count all goods before posting. Received includes damaged goods; missing goods never enter stock." actions={<Button asChild variant="outline"><a href="/receiving">All receipts</a></Button>}/><section className="panel mb-5 space-y-3 p-5"><SearchInput label="Find shipment to receive" value={search} onValueChange={setSearch} placeholder="Arrived shipment number…"/><Select aria-label="Shipment to receive" value={id} onValueChange={setID}><SelectItem value="">Choose arrived, costed shipment</SelectItem>{options.data?.map(s=><SelectItem key={s.id} value={s.id}>{s.shipment_number} · {s.warehouse_name}</SelectItem>)}</Select><p className="text-xs text-muted-foreground">Only arrived shipments with finalized landed costs can be posted. Reconcile any count mismatch with costing before receiving.</p>{options.error&&<p role="alert">{options.error.message}</p>}</section></>}{!id?<EmptyState title="Choose a shipment"/>:q.isPending?<LoadingState/>:q.error?<p role="alert">{q.error.message}</p>:q.data.status!=='ARRIVED'||!q.data.costs_finalized?<EmptyState title="Shipment is not ready for receiving" description="It must be arrived, costed and not already received."/>:<Form key={`${id}-${q.data.version}`} shipment={q.data} done={done}/>}</>
}
function Form({shipment:s,done}:{shipment:ReceivingShipment;done?:()=>void}){
 const client=useQueryClient()
 const [requestID]=useState(()=>crypto.randomUUID());const [when,setWhen]=useState(()=>localDate(new Date().toISOString()));const [notes,setNotes]=useState('');const [confirm,setConfirm]=useState(false)
 const [rows,setRows]=useState<Count[]>(()=>s.items.map(i=>({shipment_item_id:i.id,carton_size:i.carton_size||'',received_cartons:'0',received_units:i.expected_quantity,damaged_quantity:'0',batch_number:'',manufactured_on:'',expires_on:'',notes:''})))
 const update=(index:number,key:keyof Count,v:string)=>setRows(rows.map((r,i)=>i===index?{...r,[key]:v}:r))
 const valid=rows.every((r,i)=>counts(r,s.items[i])?.valid)
 const post=useMutation({mutationFn:()=>requestJSON<{id:string}>('/receiving',{method:'POST',body:JSON.stringify({request_id:requestID,shipment_id:s.id,version:s.version,received_at:iso(when),notes,items:rows})}),onSuccess:async r=>{await client.invalidateQueries({queryKey:['purchase-workflow']});await client.invalidateQueries({queryKey:['shipments']});await client.invalidateQueries({queryKey:['inventory']});if(done)done();else window.location.assign(`/receiving/${r.id}`)}})
 return <><form className="space-y-6" onSubmit={e=>{e.preventDefault();if(valid)setConfirm(true)}}>
  <fieldset disabled={post.isPending} className="panel min-w-0 space-y-5 p-4 sm:p-6">
   <div className="flex flex-wrap items-start justify-between gap-4 border-b pb-5">
    <div><h2 className="text-base font-semibold">Receipt details</h2><p className="mt-1 text-sm text-muted-foreground">Goods receipt ID is generated automatically.</p></div>
    <div className="min-w-0 sm:text-right"><p className="text-xs font-medium text-muted-foreground">Destination warehouse</p><p className="mt-1 break-words font-semibold">{s.warehouse_name}</p></div>
   </div>
   <div className="grid items-start gap-5 md:grid-cols-2"><Field label="Receiving date" value={when} onChange={setWhen} required type="datetime-local"/><OptionalSection title="Add receipt notes"><Field label="Receipt notes" value={notes} onChange={setNotes} maxLength={4000}/></OptionalSection></div>
  </fieldset>
  <div className="flex flex-wrap items-center justify-between gap-2"><h2 className="text-base font-semibold">Goods to receive</h2><p className="text-sm text-muted-foreground">{s.items.length} {s.items.length===1?'product':'products'} · Check each count and batch</p></div>
  {s.items.map((item,i)=>{const row=rows[i],p=counts(row,item);return <fieldset disabled={post.isPending} key={item.id} className="panel min-w-0 overflow-hidden">
   <div className="flex items-start gap-3 border-b bg-muted/30 p-4 sm:p-6"><span className="flex size-9 shrink-0 items-center justify-center rounded-xl border bg-white text-sm font-semibold text-muted-foreground">{i+1}</span><div className="min-w-0"><h3 className="break-words text-base font-semibold">{item.product_name}</h3><p className="mt-1 break-words text-sm text-muted-foreground">{item.sku} · Expected {amount(item.expected_quantity)} {item.base_unit} · Confirmed costing: {amount(item.sellable_quantity)} sellable {item.base_unit}{item.carton_size&&` · 1 carton = ${amount(item.carton_size)} ${item.base_unit}`}</p></div></div>
   <div className="space-y-6 p-4 sm:p-6">
    <section className="space-y-4"><h4 className="text-sm font-semibold">Received quantities</h4>
     <div className="max-w-md"><FormField label={`Received individual units ${i+1}`} required>{p=><QuantityInput {...p} value={row.received_units} onValueChange={v=>update(i,'received_units',v)} unit={item.base_unit}/>}</FormField></div>
     <div className="grid items-start gap-4 md:grid-cols-2"><OptionalSection title={`Count cartons ${i+1}`}><FormField label={`Received cartons ${i+1}`} required>{p=><QuantityInput {...p} value={row.received_cartons} onValueChange={v=>update(i,'received_cartons',v)} unit="cartons" disabled={!item.carton_size}/>}</FormField></OptionalSection><OptionalSection title={`Record damaged units ${i+1}`} defaultOpen={item.expected_quantity!==item.sellable_quantity}><FormField label={`Damaged units ${i+1}`} required>{p=><QuantityInput {...p} value={row.damaged_quantity} onValueChange={v=>update(i,'damaged_quantity',v)} unit={item.base_unit}/>}</FormField></OptionalSection></div>
     <div data-testid={`receiving-preview-${i}`} className={`rounded-xl border p-4 text-sm ${p?.valid?'border-emerald-200 bg-emerald-50 text-emerald-950':'border-amber-200 bg-amber-50 text-amber-950'}`}>
      {p?<div className="grid grid-cols-3 gap-3 tabular-nums">{[['Received',p.received],['Missing',p.missing],['Sellable',p.sellable]].map(([name,value])=><div key={name}><span className="block text-xs font-medium">{name}</span><strong className="mt-1 block text-lg">{amount(value)}</strong></div>)}</div>:'Enter valid quantities.'}
      {p&&!p.valid&&<p className="mt-3 border-t border-amber-200 pt-3">Counts must match finalized sellable quantity, with no over-receiving or excess damage.</p>}
     </div>
    </section>
    <section className="space-y-4 border-t pt-5"><h4 className="text-sm font-semibold">Batch information</h4><div className="grid items-start gap-4 md:grid-cols-2"><Field label={`Batch number ${i+1}`} value={row.batch_number} onChange={v=>update(i,'batch_number',v)} required maxLength={100}/>{item.tracks_expiry&&<Field label={`Expiry date ${i+1}`} value={row.expires_on} onChange={v=>update(i,'expires_on',v)} type="date" required/>}</div><OptionalSection title={`Manufacturing / optional expiry dates ${i+1}`}><div className="grid gap-4 md:grid-cols-2"><Field label={`Manufactured date ${i+1}`} value={row.manufactured_on} onChange={v=>update(i,'manufactured_on',v)} type="date"/>{!item.tracks_expiry&&<Field label={`Expiry date ${i+1}`} value={row.expires_on} onChange={v=>update(i,'expires_on',v)} type="date"/>}</div></OptionalSection><OptionalSection title={`Add count discrepancy notes ${i+1}`}><Field label={`Count discrepancy notes ${i+1}`} value={row.notes} onChange={v=>update(i,'notes',v)} maxLength={2000}/></OptionalSection></section>
   </div>
  </fieldset>})}
  <div className="flex flex-wrap items-center justify-between gap-4 rounded-xl border bg-white p-4"><p className="text-sm text-muted-foreground">Review all counts before posting to inventory.</p><Button className="w-full sm:w-auto" disabled={!valid||post.isPending}>Review receipt</Button></div>
 </form><ConfirmDialog open={confirm} onOpenChange={setConfirm} title="Post goods receipt?" description="This posts the complete shipment counts, creates finalized batches and stock movements, and marks the shipment received. Counts cannot be edited after posting." confirmLabel="Post receipt" onConfirm={()=>post.mutate()} busy={post.isPending} error={post.error?.message}/></>
}
