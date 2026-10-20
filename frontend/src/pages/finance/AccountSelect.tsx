import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Select, SelectItem } from '@/components/ui/select'
import { requestJSON } from '@/services/api'
export function AccountSelect({value,onChange}:{value:string;onChange:(value:string)=>void}){
 const q=useQuery({queryKey:['account-options'],queryFn:()=>requestJSON<{id:string;name:string;bank:string}[]>('/accounts/options')})
 useEffect(()=>{if(!value&&q.data?.length===1)onChange(q.data[0].id)},[value,q.data,onChange])
 if(q.error)return <p role="alert">{q.error.message}</p>
 if(q.isPending)return <p role="status">Loading accounts…</p>
 if(!q.data?.length)return <p className="text-xs text-muted-foreground">A bank/cash account is required to post payments. Ask an administrator to add an account and record its opening balance in Accounts & balances.</p>
 return <div className="space-y-1"><label className="text-sm font-medium">Bank / cash account</label><Select aria-label="Bank / cash account" value={value} onValueChange={onChange}><SelectItem value="">Choose account</SelectItem>{q.data.map(a=><SelectItem key={a.id} value={a.id}>{a.name} · {a.bank}</SelectItem>)}</Select><p className="text-xs text-muted-foreground">Account balances are in MMK. Foreign payments use their recorded exchange rate.</p></div>
}
