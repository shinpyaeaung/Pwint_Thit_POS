import { CostJourney,type PurchaseSource } from '@/components/costs/cost-journey'
import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { DataTable, FormField, QuantityInput, LoadingState, ConfirmDialog } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import { amount } from '../purchases/types'
import { Field, Money } from './Fields'

type SourceItem = {id:string;product_name:string;sku:string;base_unit_code:string;expected_quantity:string}
type Source = {version:string;status:string;finalized:boolean;transport_mmk:string;expense_mmk:string;items:SourceItem[]}
type InputItem = {id:string;sellable_quantity:string;weight_kg:string;carton_quantity:string;manual_transport_mmk:string;manual_expense_mmk:string}
type Input = {version:string;method:string;notes:string;items:InputItem[];preview_token?:string}
type CostItem = SourceItem & {sellable_quantity:string;purchase_mmk:string;transport_mmk:string;expense_mmk:string;landed_mmk:string;actual_unit_cost_mmk:string|null;weight_kg:string;carton_quantity:string}
type Result = {method:string;notes:string;purchase_mmk:string;transport_mmk:string;expense_mmk:string;landed_mmk:string;items:CostItem[];preview_token?:string;finalized:boolean}
const methods = {QUANTITY:'Quantity',PURCHASE_VALUE:'Purchase value',WEIGHT:'Weight',CARTONS:'Carton quantity',MANUAL:'Manual allocation'}
export default function LandedCost({id,current}:{id:string;current:CurrentUser}) {
 const q=useQuery({queryKey:['shipments',id,'landed-cost'],queryFn:({signal})=>requestJSON<{source:Source;snapshot:Result|null;purchase_sources:PurchaseSource[]}>(`/shipments/${id}/landed-cost`,{signal}),retry:false})
 return <section aria-label="Landed cost" className="mt-6 min-w-0"><h2 className="mb-3 text-sm font-semibold">Landed cost</h2>{q.isPending?<LoadingState/>:q.error?<div className="panel p-5"><p role="alert">{q.error.message}</p><Button onClick={()=>void q.refetch()}>Retry costing</Button></div>:q.data.snapshot?<CostResult result={q.data.snapshot} sources={q.data.purchase_sources} current={current}/>:q.data.source.finalized||q.data.source.status==='CANCELLED'?<p className="panel p-5 text-sm">This shipment is closed for costing.</p>:<CostForm key={q.data.source.version} id={id} source={q.data.source} sources={q.data.purchase_sources} current={current}/>}</section>
}
function CostForm({id,source,sources,current}:{id:string;source:Source;sources:PurchaseSource[];current:CurrentUser}) {
 const client=useQueryClient()
 const [input,setInput]=useState<Input>({version:source.version,method:'PURCHASE_VALUE',notes:'',items:source.items.map(i=>({id:i.id,sellable_quantity:i.expected_quantity,weight_kg:'',carton_quantity:'',manual_transport_mmk:'0',manual_expense_mmk:'0'}))})
 const [review,setReview]=useState<{result:Result;input:Input}|null>(null)
 const [confirm,setConfirm]=useState(false)
 const change=(next:Input)=>{setInput(next);setReview(null)}
 const line=(id:string,key:keyof InputItem,value:string)=>change({...input,items:input.items.map(i=>i.id===id?{...i,[key]:value}:i)})
 const preview=useMutation({mutationFn:(body:Input)=>requestJSON<Result>(`/shipments/${id}/landed-cost/preview`,{method:'POST',body:JSON.stringify(body)}),onSuccess:(result,body)=>setReview({result,input:body})})
 const finalize=useMutation({mutationFn:()=>requestJSON<Result>(`/shipments/${id}/landed-cost/finalize`,{method:'POST',body:JSON.stringify({...review!.input,preview_token:review!.result.preview_token})}),onSuccess:async()=>{setConfirm(false);await client.invalidateQueries({queryKey:['shipments']})}})
 const busy=preview.isPending||finalize.isPending
 return <>{!review&&<div className="mb-4"><CostJourney sources={sources} transport={source.transport_mmk} other={source.expense_mmk} canPreviewProfit={can(current,permissions.financeViewProfit)} scope="Shipment sources · allocation pending"/></div>}<form onSubmit={e=>{e.preventDefault();preview.mutate(input)}} className="panel min-w-0 space-y-5 p-5"><p className="text-sm leading-6 text-muted-foreground">Purchase cost + transportation + shipment expenses = landed cost. Each item's landed cost is divided by its sellable base quantity. Confirm the quantities below; expected quantities are only a starting estimate.</p><fieldset disabled={busy} className="min-w-0 space-y-5"><div className="grid grid-cols-1 gap-5 sm:grid-cols-2"><FormField label="Allocation method" required>{p=><Select {...p} value={input.method} onValueChange={method=>change({...input,method})}>{Object.entries(methods).map(([v,l])=><SelectItem key={v} value={v}>{l}</SelectItem>)}</Select>}</FormField><div className="text-xs leading-6 text-muted-foreground">To allocate: {amount(source.transport_mmk)} MMK transport<br/>{amount(source.expense_mmk)} MMK shipment expenses</div></div><p className="text-xs text-muted-foreground">The selected method allocates both cost pools. Weight is total kilograms per shipment item. Cartons may be fractional; enter zero for goods not packed in cartons.</p>
 {source.items.map((s,index)=>{const v=input.items[index];return <div key={s.id} className="min-w-0 rounded-xl border p-4"><h3 className="break-words text-sm font-semibold">{s.product_name}</h3><p className="mb-4 mt-1 text-xs text-muted-foreground">{s.sku} · Expected {amount(s.expected_quantity)} {s.base_unit_code}</p><div className="grid grid-cols-1 gap-4 sm:grid-cols-2"><FormField label={`Sellable quantity ${index+1}`} required>{p=><QuantityInput {...p} unit={s.base_unit_code} value={v.sellable_quantity} onValueChange={x=>line(s.id,'sellable_quantity',x)}/>}</FormField>{input.method==='WEIGHT'&&<FormField label={`Total weight (kg) ${index+1}`} required>{p=><QuantityInput {...p} unit="kg" value={v.weight_kg} onValueChange={x=>line(s.id,'weight_kg',x)}/>}</FormField>}{input.method==='CARTONS'&&<FormField label={`Carton quantity ${index+1}`} required>{p=><QuantityInput {...p} unit="cartons" value={v.carton_quantity} onValueChange={x=>line(s.id,'carton_quantity',x)}/>}</FormField>}{input.method==='MANUAL'&&<><Money label={`Manual transport (MMK) ${index+1}`} value={v.manual_transport_mmk} onChange={x=>line(s.id,'manual_transport_mmk',x)}/><Money label={`Manual expenses (MMK) ${index+1}`} value={v.manual_expense_mmk} onChange={x=>line(s.id,'manual_expense_mmk',x)}/></>}</div></div>})}
 <Field label="Costing confirmation note" value={input.notes} onChange={notes=>change({...input,notes})} maxLength={2000} required/><Button disabled={busy||!input.items.length}>{preview.isPending?'Calculating…':'Calculate landed cost'}</Button></fieldset>{preview.error&&<p role="alert" className="text-sm text-destructive">{preview.error.message}</p>}</form>
 {review&&<div className="mt-4"><CostResult result={review.result} sources={sources} current={current}/>{source.status!=='ARRIVED'?<p className="mt-3 text-xs text-muted-foreground">Preview only. Mark this shipment arrived before confirming its sellable quantities and final costs.</p>:can(current,permissions.costsFinalize)&&<Button className="mt-4" disabled={busy} onClick={()=>setConfirm(true)}>Review finalization</Button>}</div>}
 {finalize.error&&<p role="alert" className="mt-3 text-sm text-destructive">{finalize.error.message}</p>}
 <ConfirmDialog open={confirm} onOpenChange={setConfirm} title="Finalize landed cost?" description="Confirm all shipment expenses and sellable quantities are complete. This locks the allocation, transportation fees and expense history. Receiving must later reconcile with these confirmed quantities." confirmLabel="Finalize landed cost" onConfirm={()=>finalize.mutate()} busy={finalize.isPending} error={finalize.error?.message}/></>
}
function CostResult({result:r,sources,current}:{result:Result;sources:PurchaseSource[];current:CurrentUser}) {
 return <div className="min-w-0 space-y-4"><CostJourney sources={sources} converted={r.purchase_mmk} transport={r.transport_mmk} other={r.expense_mmk} landed={r.landed_mmk} finalized={r.finalized} canPreviewProfit={can(current,permissions.financeViewProfit)} zeroSellable={r.items.every(i=>i.actual_unit_cost_mmk===null)} scope={`Whole shipment · ${methods[r.method as keyof typeof methods]} allocation`} notes={r.notes}/><DataTable caption="Landed cost allocation" rows={r.items} rowKey={i=>i.id} pageSize={100} columns={[
 {id:'item',header:'Product / Sellable',cell:i=><div className="min-w-36">{i.product_name}<p className="text-xs text-muted-foreground">{amount(i.sellable_quantity)} {i.base_unit_code}</p>{r.method==='WEIGHT'&&<p className="text-xs">{amount(i.weight_kg)} kg</p>}{r.method==='CARTONS'&&<p className="text-xs">{amount(i.carton_quantity)} cartons</p>}</div>},
 {id:'purchase',header:'Purchase (MMK)',cell:i=>amount(i.purchase_mmk)},
 {id:'transport',header:'Transport (MMK)',cell:i=>amount(i.transport_mmk)},
 {id:'expense',header:'Expenses (MMK)',cell:i=>amount(i.expense_mmk)},
 {id:'landed',header:'Landed (MMK)',cell:i=><strong className="tabular-nums">{amount(i.landed_mmk)}</strong>},
 {id:'unit',header:'Actual unit cost (MMK)',cell:i=><span className="tabular-nums" data-testid="actual-unit-cost">{i.actual_unit_cost_mmk===null?'No sellable units — retain as loss':amount(i.actual_unit_cost_mmk)}</span>},
 ]}/><p className="text-xs leading-5 text-muted-foreground">MMK allocations reconcile to four decimal places; unit costs retain eight. Zero sellable quantity has no unit cost. Profit calculations must use finalized landed batch costs, never supplier purchase price alone.</p></div>
}
