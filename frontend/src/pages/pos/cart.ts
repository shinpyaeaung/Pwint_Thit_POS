import { create } from 'zustand'
export type Pack={unit_code:string;units_per_pack:string;barcode:string|null;retail_price_mmk:string|null;wholesale_price_mmk:string|null;is_default_sale:boolean}
export type Product={id:string;name:string;sku:string;barcode:string|null;base_unit_code:string;version:string;available_quantity:string;packaging:Pack[]}
export type CartLine={product:Product;unit:string;quantity:string;discount:string}
export type Mode='RETAIL'|'WHOLESALE'
export const price=(p:Pack,mode:Mode)=>mode==='RETAIL'?p.retail_price_mmk:p.wholesale_price_mmk
export function scaled(v:string,scale:number){if(!new RegExp(`^\\d{1,14}(\\.\\d{1,${scale}})?$`).test(v))throw Error('Invalid decimal');const [w,f='']=v.split('.');return BigInt(w+f.padEnd(scale,'0'))}
export function fixed(n:bigint,scale:number){const s=n.toString().padStart(scale+1,'0');return `${s.slice(0,-scale)}.${s.slice(-scale)}`}
export function lineTotal(l:CartLine,mode:Mode){try{const pack=l.product.packaging.find(p=>p.unit_code===l.unit);if(!pack||price(pack,mode)===null)return null;const q=scaled(l.quantity,6),p=scaled(price(pack,mode)!,4),d=scaled(l.discount,4);if(q<=0n||d*1000000n>q*p)return null;return fixed((q*p+500000n)/1000000n-d,4)}catch{return null}}
export const useCart=create<{lines:CartLine[];add:(p:Product,unit:string)=>void;update:(id:string,patch:Partial<CartLine>)=>void;remove:(id:string)=>void;clear:()=>void}>((set)=>({lines:[],add:(p,unit)=>set(s=>{const old=s.lines.find(l=>l.product.id===p.id);if(old)return{lines:s.lines.map(l=>l===old?{...l,quantity:fixed(scaled(l.quantity,6)+1000000n,6)}:l)};return{lines:[...s.lines,{product:p,unit,quantity:'1',discount:'0'}]}}),update:(id,patch)=>set(s=>({lines:s.lines.map(l=>l.product.id===id?{...l,...patch}:l)})),remove:id=>set(s=>({lines:s.lines.filter(l=>l.product.id!==id)})),clear:()=>set({lines:[]})}))
