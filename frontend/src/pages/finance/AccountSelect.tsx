import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Select, SelectItem } from '@/components/ui/select'
import { requestJSON } from '@/services/api'
export function AccountSelect({value,onChange,method}:{value:string;onChange:(value:string)=>void;method?:string}){
 const q=useQuery({queryKey:['account-options'],queryFn:()=>requestJSON<{id:string;name:string;bank:string;account_type:string;holder:string}[]>('/accounts/options')})
 const type=method==='CASH'?'CASH':method&&method!=='OTHER'?'BANK':undefined
 const accounts=q.data?.filter(a=>a.account_type!=='UNCLASSIFIED'&&(!type||a.account_type===type))
 useEffect(()=>{if(!accounts)return;if(value&&!accounts.some(a=>a.id===value))onChange('');else if(!value&&accounts.length===1)onChange(accounts[0].id)},[value,accounts,onChange])
 if(q.error)return <p role="alert">{q.error.message}</p>
 if(q.isPending)return <p role="status">Loading accounts…</p>
 if(!accounts?.length)return <p className="text-xs text-muted-foreground">No active {type==='CASH'?'cash':type==='BANK'?'bank':'bank/cash'} accounts available. Add or classify an account in Accounts &amp; balances.</p>
 return <div className="space-y-1"><label className="text-sm font-medium">{type==='CASH'?'Cash account':type==='BANK'?'Bank account':'Bank / cash account'}</label><Select aria-label="Bank / cash account" value={value} onValueChange={onChange}><SelectItem value="">Choose account</SelectItem>{accounts.map(a=><SelectItem key={a.id} value={a.id}>{a.name} · {a.bank||'Cash'}</SelectItem>)}</Select><p className="text-xs text-muted-foreground">Select the business account that pays or receives this money.</p></div>
}
