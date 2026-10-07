import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Modal, FormField, CurrencyInput } from '@/components/shared'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { requestJSON } from '@/services/api'
import { amount } from '../purchases/types'
import type { Product } from './cart'
import { costPerPack, sellingPrices, type PricingCost } from './landed-pricing'

export function PriceEditor({product:p,warehouse,onClose}:{product:Product;warehouse:string;onClose:()=>void}){
 const client=useQueryClient()
 const [unit,setUnit]=useState(p.packaging.find(u=>u.unit_code==='CARTON')?.unit_code||p.packaging.find(u=>u.unit_code!==p.base_unit_code)?.unit_code||p.base_unit_code)
 const [reference,setReference]=useState(''),[mode,setMode]=useState('PER_UNIT')
 const base=p.packaging.find(u=>u.unit_code===p.base_unit_code)
 const [retail,setRetail]=useState(base?.retail_price_mmk||''),[wholesale,setWholesale]=useState(base?.wholesale_price_mmk||'')
 const pack=p.packaging.find(u=>u.unit_code===unit)
 const costs=useQuery({queryKey:['pricing-costs',warehouse,p.id],queryFn:()=>requestJSON<PricingCost[]>(`/pos/pricing-costs?warehouse_id=${warehouse}&product_id=${p.id}`)})
 const source=costs.data?.find(c=>c.shipment_item_id===reference)||costs.data?.[0]
 const contents=pack?.units_per_pack||'1'
 const retailPrices=sellingPrices(source,mode,retail,contents),wholesalePrices=sellingPrices(source,mode,wholesale,contents)
 const save=useMutation({mutationFn:()=>requestJSON('/pos/landed-prices',{method:'PUT',body:JSON.stringify({warehouse_id:warehouse,product_id:p.id,shipment_item_id:source?.shipment_item_id,unit_code:unit,version:p.version,mode,retail_value:retail,wholesale_value:wholesale})}),onSuccess:async()=>{await client.invalidateQueries({queryKey:['pos-products']});onClose()}})
 return <Modal open onOpenChange={v=>{if(!v)onClose()}} title="Set warehouse selling prices" description={p.name} busy={save.isPending}>
  <form className="space-y-4" onSubmit={e=>{e.preventDefault();if(retailPrices&&wholesalePrices)save.mutate()}}>
   {costs.isPending&&<p role="status">Loading finalized landed costs…</p>}
   {costs.error&&<p role="alert">{costs.error.message} Purchase-cost and landed-cost viewing permissions are required.</p>}
   {costs.data?.length===0&&<p role="status">No finalized landed cost for this product at this warehouse. Complete the purchase and shipment costing first, then return here to set selling prices.</p>}
   {source&&<>
    <FormField label="Finalized cost reference">{f=><Select {...f} value={source.shipment_item_id} onValueChange={setReference}>{costs.data?.map(c=><SelectItem key={c.shipment_item_id} value={c.shipment_item_id}>{c.shipment_number} · {c.purchase_number} · {c.sellable_quantity} {p.base_unit_code}</SelectItem>)}</Select>}</FormField>
    <FormField label="Pricing unit">{f=><Select {...f} value={unit} onValueChange={setUnit}>{p.packaging.map(u=><SelectItem key={u.unit_code} value={u.unit_code}>{u.unit_code} · {u.units_per_pack} base units</SelectItem>)}</Select>}</FormField>
    <p className="text-xs text-muted-foreground">1 {unit} = {amount(contents)} {p.base_unit_code}. Costs use the selected shipment’s confirmed sellable quantity, including any receiving loss allocation.</p>
    <div className="overflow-x-auto rounded-lg border"><table className="w-full text-left text-sm" aria-label="Landed cost breakdown"><thead className="bg-muted"><tr><th className="p-2">Cost (MMK)</th><th className="p-2">Per {unit}</th><th className="p-2">Per {p.base_unit_code}</th></tr></thead><tbody>{[['Purchase cost',source.purchase_cost_mmk],['Cargo fees',source.cargo_cost_mmk],['Additional costs',source.additional_cost_mmk],['Landed cost',source.landed_cost_mmk]].map(([label,total])=><tr className="border-t" key={label}><th className="p-2 font-medium">{label}</th><td className="p-2 tabular-nums">{amount(costPerPack(total,source.sellable_quantity,contents))}</td><td className="p-2 tabular-nums">{amount(costPerPack(total,source.sellable_quantity,'1'))}</td></tr>)}</tbody></table></div>
    <FormField label="Set selling prices by">{f=><Select {...f} value={mode} onValueChange={v=>{setMode(v);setRetail('');setWholesale('')}}><SelectItem value="PER_UNIT">Price per {p.base_unit_code}</SelectItem><SelectItem value="MARKUP">Percentage markup on landed cost</SelectItem></Select>}</FormField>
    <FormField label={mode==='MARKUP'?'Retail markup (%)':`Retail price per ${p.base_unit_code}`} required>{f=><CurrencyInput {...f} currency={mode==='MARKUP'?'%':'MMK'} value={retail} onValueChange={setRetail}/>}</FormField>
    <FormField label={mode==='MARKUP'?'Wholesale markup (%)':`Wholesale price per ${p.base_unit_code}`} required>{f=><CurrencyInput {...f} currency={mode==='MARKUP'?'%':'MMK'} value={wholesale} onValueChange={setWholesale}/>}</FormField>
    <div className="rounded-lg bg-muted p-3 text-sm" aria-label="Calculated selling prices"><p>Retail: {retailPrices?`${amount(retailPrices.base)} MMK / ${p.base_unit_code} · ${amount(retailPrices.pack)} MMK / ${unit}`:'Enter a valid retail price or markup.'}</p><p>Wholesale: {wholesalePrices?`${amount(wholesalePrices.base)} MMK / ${p.base_unit_code} · ${amount(wholesalePrices.pack)} MMK / ${unit}`:'Enter a valid wholesale price or markup.'}</p></div>
    <p className="text-xs text-muted-foreground">Saves {p.base_unit_code} and {unit} prices together for this warehouse. Individual prices round to 4 decimal places; package price = individual price × contents. {mode==='MARKUP'&&'Markup = landed cost × (1 + percentage ÷ 100).'}</p>
   </>}
   {save.error&&<p role="alert">{save.error.message}</p>}
   <Button disabled={save.isPending||!retailPrices||!wholesalePrices}>Save prices</Button>
  </form>
 </Modal>
}
