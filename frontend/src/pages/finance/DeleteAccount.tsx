import {useState} from 'react'
import {useMutation,useQuery,useQueryClient} from '@tanstack/react-query'
import {Modal} from '@/components/shared'
import {Button} from '@/components/ui/button'
import {Field} from '../shipments/Fields'
import {amount} from '../purchases/types'
import {ApiError,requestJSON} from '@/services/api'
type Preview={name:string;fingerprint:string;balance_mmk:string;entries:number;payments:number;allocations:number;personal_transactions:number}
export default function DeleteAccount({id,close,deleted}:{id:string;close:()=>void;deleted:()=>void}){
 const client=useQueryClient(),[request]=useState(()=>crypto.randomUUID()),[confirmation,setConfirmation]=useState(''),[reason,setReason]=useState('')
 const preview=useQuery({queryKey:['account-delete-preview',id],queryFn:()=>requestJSON<Preview>(`/accounts/${id}/delete-preview`),refetchOnWindowFocus:false})
 const [submitted,setSubmitted]=useState<string|null>(null)
 const remove=useMutation({mutationFn:()=>{const body=submitted||JSON.stringify({request_id:request,fingerprint:preview.data?.fingerprint,confirmation,reason});setSubmitted(body);return requestJSON(`/accounts/${id}`,{method:'DELETE',body})},onSuccess:async()=>{await client.invalidateQueries({predicate:q=>q.queryKey[0]!=='account-delete-preview'});deleted()},onError:e=>{if(e instanceof ApiError&&e.status>0&&e.status<500)setSubmitted(null)}})
 const locked=remove.isPending||submitted!==null
 const p=preview.data
 return <Modal open title="Delete account permanently" busy={locked} onOpenChange={open=>!open&&!locked&&close()} footer={<Button variant="destructive" disabled={remove.isPending||!p||confirmation!==p.name||!reason.trim()} onClick={()=>remove.mutate()}>{submitted?'Retry deletion':'Delete permanently'}</Button>}>
 <div className="space-y-4"><p>This permanently removes the account from the database, account lists and payment selections. It cannot be restored.</p>{p&&<><p className="font-semibold">{p.name} · {amount(p.balance_mmk)} MMK</p><ul className="list-disc pl-5"><li>{p.entries} account entries</li><li>{p.payments} payments and {p.allocations} invoice allocations</li><li>{p.personal_transactions} personal loan or gift records</li></ul><p>Payment history will be erased. Linked invoices may become unpaid; customer balances, debts and financial reports will change. Purchases, sales, stock records and security audit records remain.</p><fieldset disabled={locked} className="space-y-3"><Field label={`Type account name: ${p.name}`} value={confirmation} onChange={setConfirmation}/><Field label="Deletion reason" value={reason} onChange={setReason}/></fieldset></>}{preview.isPending&&<p>Loading deletion details…</p>}{preview.error&&<p role="alert">{preview.error.message}</p>}{remove.error&&<p role="alert">{remove.error.message}</p>}</div>
 </Modal>
}
