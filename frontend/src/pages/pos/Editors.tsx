import { useState } from 'react'
import { useMutation,useQueryClient } from '@tanstack/react-query'
import { Modal,FormField,CurrencyInput } from '@/components/shared'
import { Button } from '@/components/ui/button'
import { Select,SelectItem } from '@/components/ui/select'
import { requestJSON } from '@/services/api'
import { Field } from '../shipments/Fields'
export { PriceEditor } from './PriceEditor'
export function CustomerEditor({onClose,onSaved}:{onClose:()=>void;onSaved:(id:string,name:string)=>void}){
 const [name,setName]=useState(''),[phone,setPhone]=useState(''),[type,setType]=useState('RETAIL'),[limit,setLimit]=useState('0');const client=useQueryClient()
 const save=useMutation({mutationFn:()=>requestJSON<{id:string}>('/pos/customers',{method:'POST',body:JSON.stringify({name,phone,customer_type:type,credit_limit_mmk:limit})}),onSuccess:async r=>{await client.invalidateQueries({queryKey:['pos-customers']});onSaved(r.id,name);onClose()}})
 return <Modal open onOpenChange={v=>{if(!v)onClose()}} title="Add customer" busy={save.isPending}><form className="space-y-4" onSubmit={e=>{e.preventDefault();save.mutate()}}><Field label="Customer name" value={name} onChange={setName} required maxLength={150}/><Field label="Customer phone" value={phone} onChange={setPhone} maxLength={100}/><Select aria-label="Customer type" value={type} onValueChange={setType}><SelectItem value="RETAIL">Retail</SelectItem><SelectItem value="WHOLESALE">Wholesale</SelectItem></Select><FormField label="Credit limit (MMK)" required>{f=><CurrencyInput {...f} value={limit} onValueChange={setLimit}/>}</FormField><p className="text-xs text-muted-foreground">A zero limit requires full payment.</p>{save.error&&<p role="alert">{save.error.message}</p>}<Button disabled={save.isPending}>Save customer</Button></form></Modal>
}
