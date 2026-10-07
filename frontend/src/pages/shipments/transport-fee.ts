// Exact positive decimal arithmetic, matching PostgreSQL NUMERIC rounding.
const units=(v:string,digits:number,scale:number)=>{if(!new RegExp(`^\\d{1,${digits}}(\\.\\d{1,${scale}})?$`).test(v))throw Error('Invalid fee');const [w,f='']=v.split('.');return BigInt(w+f.padEnd(scale,'0'))}
const money=(n:bigint)=>{const v=n.toString().padStart(5,'0');return `${v.slice(0,-4)}.${v.slice(-4)}`}
export function transportFee(values:Record<string,string>){
 try{
  let transport=0n
  if(values.fee_basis==='PER_PACKAGE'){
   const count=units(values.package_quantity,14,6);if(count<=0n)return null
   transport=(units(values.fee_per_package_mmk,16,4)*count+500000n)/1000000n
  }else transport=units(values.transportation_fee_mmk,16,4)
  const total=transport+units(values.loading_fee_mmk,16,4)+units(values.unloading_fee_mmk,16,4)+units(values.other_fee_mmk,16,4)
  if(total>=100000000000000000000n)return null
  return {transport:money(transport),total:money(total)}
 }catch{return null}
}
