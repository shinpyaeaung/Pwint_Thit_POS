import { amount } from '../purchases/types'
import type { Choice } from './types'
const quantity=(v:string)=>{if(!/^\d{1,14}(\.\d{1,6})?$/.test(v))throw Error('Invalid quantity');const [w,f='']=v.split('.');return BigInt(w+f.padEnd(6,'0'))}
const decimal=(v:bigint)=>{const s=v.toString().padStart(7,'0');return `${s.slice(0,-6)}.${s.slice(-6)}`}
export function shipmentQuantity(value:string,item:Pick<Choice,'base_unit_code'|'carton_size'|'package_type'|'package_size'>){
 try{
  const total=quantity(value)
  const unit=(n:bigint)=>item.base_unit_code==='BOTTLE'?(n===1000000n?'bottle':'bottles'):item.base_unit_code==='PIECE'?(n===1000000n?'piece':'pieces'):(item.base_unit_code||'base units')
  const base=`${amount(value)} ${unit(total)}`
  const packSize=item.package_size||item.carton_size
  if(!packSize)return base
  const pack=(item.package_type||'CARTON').toLowerCase().replaceAll('_',' ')
  const size=quantity(packSize);if(size<=0n||(size===1000000n&&item.package_type===item.base_unit_code))return base
  const cartons=total/size,remainder=total%size
  const packages=`${cartons.toLocaleString('en-US')} ${pack}${cartons===1n?'':'s'}`
  return `${packages}${remainder?` + ${amount(decimal(remainder))} ${unit(remainder)}`:''} (${base})`
 }catch{return 'Enter a valid quantity'}
}
