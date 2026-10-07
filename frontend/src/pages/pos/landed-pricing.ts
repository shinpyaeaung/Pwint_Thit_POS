import { fixed, scaled } from './cart'
export type PricingCost = { shipment_item_id:string; shipment_id:string; shipment_number:string; purchase_number:string; finalized_at:string; purchase_cost_mmk:string; cargo_cost_mmk:string; additional_cost_mmk:string; landed_cost_mmk:string; sellable_quantity:string }
// Stored cost totals can be wider than an editable price (NUMERIC(20,4)).
const stored=(value:string,scale:number)=>{if(!/^\d+(\.\d+)?$/.test(value))throw Error('Invalid cost');const [w,f='']=value.split('.');if(f.length>scale)throw Error('Invalid cost precision');return BigInt(w+f.padEnd(scale,'0'))}
const rounded=(n:bigint,d:bigint)=>{if(d<=0n)throw Error('No sellable quantity');return (n+d/2n)/d}
export function costPerPack(total:string,quantity:string,contents:string){
 return fixed(rounded(stored(total,4)*scaled(contents,6),scaled(quantity,6)),4)
}
export function sellingPrices(source:PricingCost|undefined,mode:string,value:string,contents:string){
 try{
  if(!source)return null
  const input=scaled(value,4)
  const base=mode==='MARKUP'?rounded(stored(source.landed_cost_mmk,4)*(1000000n+input),scaled(source.sellable_quantity,6)):input
  if(base<=0n)return null
  return {base:fixed(base,4),pack:fixed(rounded(base*scaled(contents,6),1000000n),4)}
 }catch{return null}
}
