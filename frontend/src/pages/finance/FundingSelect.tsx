import { useQuery } from '@tanstack/react-query'
import { Select,SelectItem } from '@/components/ui/select'
import { requestJSON } from '@/services/api'
import { AccountSelect } from './AccountSelect'
export function FundingSelect({account,creditor,onAccount,onCreditor,method}:{account:string;creditor:string;onAccount:(v:string)=>void;onCreditor:(v:string)=>void;method?:string}){
 const thirdParty=creditor!==''
 const q=useQuery({queryKey:['creditor-options'],queryFn:()=>requestJSON<{id:string;name:string}[]>('/creditors/options')})
 return <div className="space-y-3"><Select aria-label="Payment funding" value={thirdParty?'THIRD_PARTY':'ACCOUNT'} onValueChange={v=>{onAccount('');onCreditor(v==='THIRD_PARTY'?'choose':'')}}><SelectItem value="ACCOUNT">Business bank / cash account</SelectItem><SelectItem value="THIRD_PARTY">Another person pays — money owed to them</SelectItem></Select>{thirdParty?<><Select aria-label="Paying creditor" value={creditor==='choose'?'':creditor} onValueChange={onCreditor}><SelectItem value="">Choose person</SelectItem>{q.data?.map(c=><SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}</Select>{q.error&&<p role="alert">{q.error.message}</p>}<p className="text-xs text-muted-foreground">This settles the business payment and creates a separate payable to this person. Your bank/cash balance is unchanged. Add people in <a className="underline" href="/accounts?category=people">Other People’s Accounts</a>.</p></>:<AccountSelect value={account} onChange={onAccount} method={method}/>}</div>
}
