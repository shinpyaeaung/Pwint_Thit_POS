import {useEffect} from 'react'
import {useQuery} from '@tanstack/react-query'
import {Select,SelectItem} from '@/components/ui/select'
import {requestJSON} from '@/services/api'
export function SupplierFunding({method,account,creditor,onAccount,onCreditor}:{method:string;account:string;creditor:string;onAccount:(v:string)=>void;onCreditor:(v:string)=>void}){
 const accounts=useQuery({queryKey:['account-options'],queryFn:()=>requestJSON<{id:string;name:string;bank:string;account_type:string;holder:string;last_digits:string}[]>('/accounts/options')})
 const people=useQuery({queryKey:['creditor-options'],queryFn:()=>requestJSON<{id:string;name:string}[]>('/creditors/options')})
 const choices=accounts.data?.filter(a=>a.account_type===(method==='CASH'?'CASH':'BANK'))
 useEffect(()=>{if(!account&&!creditor&&choices?.length===1)onAccount(choices[0].id)},[account,creditor,choices,onAccount])
 return <div className="space-y-2"><label className="text-sm font-medium">{method==='CASH'?'Paying cash account':'Paying bank account'}</label><Select aria-label="Paying account" value={creditor?`person:${creditor}`:account} onValueChange={v=>{onCreditor(v.startsWith('person:')?v.slice(7):'');onAccount(v.startsWith('person:')?'':v)}}><SelectItem value="">Choose paying account</SelectItem>{choices?.map(a=><SelectItem key={a.id} value={a.id}>{a.account_type==='BANK'?`${a.bank} · ${a.holder||a.name}${a.last_digits?` · •••• ${a.last_digits}`:''}`:a.name}</SelectItem>)}{people.data?.map(p=><SelectItem key={p.id} value={`person:${p.id}`}>Other person · {p.name}</SelectItem>)}</Select>{creditor?<p className="text-xs text-muted-foreground">This person pays the supplier on your behalf. The amount becomes money you owe them; business cash is unchanged.</p>:<p className="text-xs text-muted-foreground">Only active {method==='CASH'?'cash':'bank'} accounts are shown. Manage accounts and people in Accounts &amp; balances.</p>}{(accounts.error||people.error)&&<p role="alert">{accounts.error?.message||people.error?.message}</p>}</div>
}
