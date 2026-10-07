import { amount } from '../purchases/types'
import type { Choice } from './types'
const quantity=(v:string)=>{if(!/^\d{1,14}(\.\d{1,6})?$/.test(v))throw Error('Invalid quantity');const [w,f='']=v.split('.');return BigInt(w+f.padEnd(6,'0'))}
const decimal=(v:bigint)=>{const s=v.toString().padStart(7,'0');return `${s.slice(0,-6)}.${s.slice(-6)}`}
export function shipmentQuantity(value:string,item:Choice){
 try{
  const total=quantity(value)
  const unit=(n:bigint)=>item.base_unit_code==='BOTTLE'?(n===1000000n?'bottle':'bottles'):item.base_unit_code==='PIECE'?(n===1000000n?'piece':'pieces'):(item.base_unit_code||'base units')
  const base=`${amount(value)} ${unit(total)}`
  if(!item.carton_size)return `${base} · carton size not set`
  const size=quantity(item.carton_size);if(size<=0n)return base
  const cartons=total/size,remainder=total%size
  const packages=`${cartons.toLocaleString('en-US')} ${cartons===1n?'carton':'cartons'}`
  return `${packages}${remainder?` + ${amount(decimal(remainder))} ${unit(remainder)}`:''} (${base})`
 }catch{return 'Enter a valid quantity'}
}
