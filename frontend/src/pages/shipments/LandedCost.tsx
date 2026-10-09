import { cartonCost } from '../receiving/types'
import { CostJourney,type PurchaseSource } from '@/components/costs/cost-journey'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { DataTable, LoadingState } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { type CurrentUser } from '@/permissions'
import { amount } from '../purchases/types'

type SourceItem = {carton_size?:string|null;id:string;product_name:string;sku:string;base_unit_code:string;expected_quantity:string}
type Source = {version:string;status:string;finalized:boolean;transport_mmk:string;expense_mmk:string;items:SourceItem[]}
type CostItem = SourceItem & {received_quantity?:string;damaged_quantity?:string;sellable_quantity:string;purchase_mmk:string;transport_mmk:string;expense_mmk:string;landed_mmk:string;actual_unit_cost_mmk:string|null;weight_kg:string;carton_quantity:string}
export type Result = {counts_confirmed?:boolean;method:string;notes:string;purchase_mmk:string;transport_mmk:string;expense_mmk:string;landed_mmk:string;items:CostItem[];preview_token?:string;finalized:boolean}
const methods = {QUANTITY:'Quantity',PURCHASE_VALUE:'Purchase value',WEIGHT:'Weight',CARTONS:'Carton quantity',MANUAL:'Manual allocation'}
export default function LandedCost({id,current}:{id:string;current:CurrentUser}) {
 const q=useQuery({queryKey:['shipments',id,'landed-cost'],queryFn:({signal})=>requestJSON<{source:Source;snapshot:Result|null;purchase_sources:PurchaseSource[]}>(`/shipments/${id}/landed-cost`,{signal}),retry:false})
 return <section aria-label="Landed cost" className="mt-6 min-w-0"><h2 className="mb-3 text-sm font-semibold">Landed cost</h2>{q.isPending?<LoadingState/>:q.error?<div className="panel p-5"><p role="alert">{q.error.message}</p><Button onClick={()=>void q.refetch()}>Retry costing</Button></div>:q.data.snapshot?<CostResult result={q.data.snapshot} sources={q.data.purchase_sources} items={q.data.source.items}/>:q.data.source.finalized||q.data.source.status==='CANCELLED'?<p className="panel p-5 text-sm">This shipment is closed for costing.</p>:<CostForm key={q.data.source.version} id={id} source={q.data.source} sources={q.data.purchase_sources} current={current}/>}</section>
}
function CostForm({id,source,sources}:{id:string;source:Source;sources:PurchaseSource[];current:CurrentUser}) {
 const preview=useMutation({mutationFn:()=>requestJSON<Result>(`/shipments/${id}/landed-cost/preview`,{method:'POST',body:JSON.stringify({version:source.version,method:'PURCHASE_VALUE',notes:'',items:source.items.map(i=>({id:i.id,sellable_quantity:'',received_quantity:'',damaged_quantity:'',weight_kg:'',carton_quantity:'',manual_transport_mmk:'0',manual_expense_mmk:'0'}))})})})
 return <div className="panel space-y-4 p-5"><p className="text-sm text-muted-foreground">Purchase cost + cargo + additional costs = landed cost. This estimate uses expected quantities. Enter received, damaged and lost goods on Receive Goods into Inventory to confirm the final costs. Cargo and additional costs are allocated automatically by purchase value.</p><CostJourney sources={sources} transport={source.transport_mmk} other={source.expense_mmk} canPreviewProfit={false} scope="Shipment cost estimate"/><Button onClick={()=>preview.mutate()} disabled={preview.isPending}>Calculate landed cost</Button>{preview.error&&<p role="alert">{preview.error.message}</p>}{preview.data&&<CostResult result={preview.data} sources={sources} items={source.items}/>}</div>
}
export function CostResult({result:r,sources=[],items=[]}:{result:Result;sources?:PurchaseSource[];items?:SourceItem[]}) {
 return <div className="min-w-0 space-y-4"><CostJourney sources={sources} converted={r.purchase_mmk} transport={r.transport_mmk} other={r.expense_mmk} landed={r.landed_mmk} finalized={r.finalized} canPreviewProfit={false} zeroSellable={r.items.every(i=>i.actual_unit_cost_mmk===null)} scope={`Whole shipment · ${methods[r.method as keyof typeof methods]} allocation`} notes={r.notes}/><DataTable caption="Landed cost allocation" rows={r.items} rowKey={i=>i.id} pageSize={100} columns={[
 {id:'item',header:r.counts_confirmed||r.finalized?'Product / Sellable':'Product / Expected (estimate)',cell:i=><div className="min-w-36">{i.product_name}<p className="text-xs text-muted-foreground">{amount(i.sellable_quantity)} {i.base_unit_code}</p>{i.received_quantity!==undefined&&<p className="text-xs text-muted-foreground">Received {amount(i.received_quantity)} − damaged {amount(i.damaged_quantity)}</p>}{r.method==='WEIGHT'&&<p className="text-xs">{amount(i.weight_kg)} kg</p>}{r.method==='CARTONS'&&<p className="text-xs">{amount(i.carton_quantity)} cartons</p>}</div>},
 {id:'purchase',header:'Purchase (MMK)',cell:i=>amount(i.purchase_mmk)},
 {id:'transport',header:'Transport (MMK)',cell:i=>amount(i.transport_mmk)},
 {id:'expense',header:'Expenses (MMK)',cell:i=>amount(i.expense_mmk)},
 {id:'landed',header:'Landed (MMK)',cell:i=><strong className="tabular-nums">{amount(i.landed_mmk)}</strong>},
 {id:'carton',header:'Landed Cost per Carton (MMK)',cell:i=>amount(cartonCost(i.actual_unit_cost_mmk,i.carton_size??items.find(x=>x.id===i.id)?.carton_size))},
 {id:'unit',header:'Landed Cost per Piece (MMK)',cell:i=><span className="tabular-nums" data-testid="actual-unit-cost">{i.actual_unit_cost_mmk===null?'No sellable units — retain as loss':amount(i.actual_unit_cost_mmk)}</span>},
 ]}/><p className="text-xs leading-5 text-muted-foreground">MMK allocations reconcile to four decimal places; unit costs retain eight. Zero sellable quantity has no unit cost. Profit calculations must use finalized landed batch costs, never supplier purchase price alone.</p></div>
}
