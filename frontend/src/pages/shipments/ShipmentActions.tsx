import { useState } from 'react'
import { useMutation,useQuery,useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { Select,SelectItem } from '@/components/ui/select'
import { FormField } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { can,permissions,type CurrentUser } from '@/permissions'
import { Field,Money } from './Fields'
import { iso,localDate,type Shipment,type Stage } from './types'
export type Action = {kind:'stage';stage?:Stage}|{kind:'expense'}|{kind:'void';id:string}|{kind:'status';status:string}
export default function ShipmentActions({s,action,current,done}:{s:Shipment;action:Action;current:CurrentUser;done:()=>void}) {
 const client=useQueryClient(); const old=action.kind==='stage'?action.stage:undefined
 const [requestID]=useState(()=>crypto.randomUUID()); const [version]=useState(s.version)
 const [values,setValues]=useState<Record<string,string>>(():Record<string,string>=>action.kind==='stage'?{start_location:old?.start_location||s.last_destination||s.start_location,destination:old?.destination||'',provider_name:old?.provider_name||'',transportation_type:old?.transportation_type||'',vehicle_information:old?.vehicle_information||'',departed_at:localDate(old?.departed_at),arrived_at:localDate(old?.arrived_at),transportation_fee_mmk:old?.transportation_fee_mmk||'0',loading_fee_mmk:old?.loading_fee_mmk||'0',unloading_fee_mmk:old?.unloading_fee_mmk||'0',other_fee_mmk:old?.other_fee_mmk||'0',notes:old?.notes||''}:action.kind==='expense'?{category:'',description:'',currency_code:'MMK',amount_original:'',mmk_per_unit:'1',incurred_at:localDate(new Date().toISOString()),notes:''}:action.kind==='void'?{reason:''}:{shipped_at:localDate(new Date().toISOString()),arrived_at:localDate(new Date().toISOString())})
 const set=(k:string,v:string)=>setValues(p=>({...p,[k]:v}))
 const currencies=useQuery({queryKey:['currencies'],queryFn:()=>requestJSON<{code:string}[]>('/currencies'),enabled:action.kind==='expense'})
 const mutation=useMutation({mutationFn:()=>{
  let endpoint='',method='POST';let body:Record<string,string>={...values,version}
  if(action.kind==='stage'){endpoint=`stages${old?`/${old.id}`:''}`;method=old?'PUT':'POST';body={...body,request_id:requestID,departed_at:iso(values.departed_at),arrived_at:iso(values.arrived_at)}}
  if(action.kind==='expense'){endpoint='expenses';body={...body,request_id:requestID,incurred_at:iso(values.incurred_at)}}
  if(action.kind==='void')endpoint=`expenses/${action.id}/void`
  if(action.kind==='status'){endpoint='status';method='PUT';body={version,status:action.status,shipped_at:action.status==='IN_TRANSIT'?iso(values.shipped_at):'',arrived_at:action.status==='ARRIVED'?iso(values.arrived_at):''}}
  return requestJSON(`/shipments/${s.id}/${endpoint}`,{method,body:JSON.stringify(body)})
 },onSuccess:async()=>{await client.invalidateQueries({queryKey:['shipments']});done()}})
 const field=(key:string,title:string,required=false,type='text',maxLength=200)=><Field key={key} label={title} value={values[key]||''} onChange={v=>set(key,v)} required={required} type={type} maxLength={maxLength}/>
 return <form className="space-y-4" onSubmit={e=>{e.preventDefault();mutation.mutate()}}><fieldset disabled={mutation.isPending} className="grid min-w-0 grid-cols-1 gap-4">
 {action.kind==='stage'&&<>{field('start_location','Stage origin',true)}{field('destination','Destination',true)}{field('provider_name','Provider',true)}{field('transportation_type','Transport type',false,'text',100)}{field('vehicle_information','Vehicle information')}<div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{field('departed_at','Stage departure',false,'datetime-local')}{field('arrived_at','Stage arrival',false,'datetime-local')}</div>{[['transportation_fee_mmk','Transportation fee (MMK)'],['loading_fee_mmk','Loading fee (MMK)'],['unloading_fee_mmk','Unloading fee (MMK)'],['other_fee_mmk','Additional charges (MMK)']].map(([k,l])=><Money key={k} label={l} value={values[k]} onChange={v=>set(k,v)}/>)}{field('notes','Stage notes',false,'text',4000)}<p className="text-xs text-muted-foreground">Payment status follows posted payment allocations. Paid stages cannot be edited here.</p></>}
 {action.kind==='expense'&&<>{field('category','Category',true,'text',100)}{field('description','Description',true,'text',1000)}<FormField label="Expense currency" required>{p=><Select {...p} value={values.currency_code} onValueChange={v=>{set('currency_code',v);set('mmk_per_unit',v==='MMK'?'1':'')}}>{(currencies.data||[{code:'MMK'}]).filter(c=>c.code==='MMK'||can(current,permissions.exchangeRatesManage)).map(c=><SelectItem key={c.code} value={c.code}>{c.code}</SelectItem>)}</Select>}</FormField><Money label="Original amount" value={values.amount_original} onChange={v=>set('amount_original',v)}/><Money label="MMK per currency unit" value={values.mmk_per_unit} onChange={v=>set('mmk_per_unit',v)} rate readOnly={values.currency_code==='MMK'}/>{field('incurred_at','Expense date',true,'datetime-local')}{field('notes','Expense notes',false,'text',4000)}<p className="text-xs text-muted-foreground">The transaction rate is saved permanently. To correct an expense, void it with a reason and add a replacement.</p>{currencies.error&&<p role="alert">{currencies.error.message}</p>}</>}
 {action.kind==='void'&&field('reason','Void reason',true,'text',1000)}
 {action.kind==='status'&&(action.status==='CANCELLED'?<p className="text-sm">Cancel this shipment and release its purchased quantities? Transportation and expense history will be retained.</p>:action.status==='IN_TRANSIT'?field('shipped_at','Shipment departure',true,'datetime-local'):field('arrived_at','Warehouse arrival',true,'datetime-local'))}
 </fieldset>{mutation.error&&<p role="alert" className="text-sm text-destructive">{mutation.error.message} If another user changed this shipment, close this form and reload before retrying.</p>}<Button disabled={mutation.isPending}>{mutation.isPending?'Saving…':'Save changes'}</Button></form>
}
