import { amount } from '@/pages/purchases/types'
export function PaymentBalance({ total, paid, remaining, currency }: { total: string; paid: string; remaining: string; currency: string }) {
  return <dl className="min-w-40 space-y-1 text-xs">{[['Total',total],['Paid',paid],['Remaining',remaining]].map(([label,value])=><div key={label} className={`flex justify-between gap-4 ${label==='Remaining'?'border-t pt-1 font-semibold':''}`}><dt className="text-muted-foreground">{label}</dt><dd className="whitespace-nowrap text-right tabular-nums">{amount(value)} {currency}</dd></div>)}</dl>
}
