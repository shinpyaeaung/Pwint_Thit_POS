import { useState } from 'react'
import { ArrowDown, ArrowRight, Route } from 'lucide-react'
import { motion, useReducedMotion } from 'framer-motion'
import { CurrencyInput, FormField, StatusBadge } from '@/components/shared'
import { amount } from '@/pages/purchases/types'
export type PurchaseSource = {amount:string;currency:string;rate:string;reference:string;quantity?:string;allocated_quantity?:string}
type Props = {sources?:PurchaseSource[];converted?:string|null;transport?:string|null;other?:string|null;landed?:string|null;finalized?:boolean;canPreviewProfit?:boolean;scope:string;notes?:string;zeroSellable?:boolean;examplePrice?:string}
// Exact signed decimal subtraction, including the eight-decimal unit-cost scale.
function profitPreview(selling:string,landed:string):string|null {
 const parse=(v:string)=>{if(!/^\d{1,16}(\.\d{1,8})?$/.test(v))throw Error();const [w,f='']=v.split('.');return BigInt(w+f.padEnd(8,'0'))}
 try{const n=parse(selling)-parse(landed);const s=(n<0n?-n:n).toString().padStart(9,'0');return `${n<0n?'-':''}${s.slice(0,-8)}.${s.slice(-8)}`}catch{return null}
}
export function CostJourney({sources=[],converted,transport,other,landed,finalized=false,canPreviewProfit=false,scope,notes,zeroSellable=false,examplePrice}:Props){
 const reduced=useReducedMotion();const [selling,setSelling]=useState(examplePrice||'')
 const canEstimate=canPreviewProfit&&landed!=null&&!zeroSellable
 const profit=canEstimate&&selling?profitPreview(selling,landed):null
 const source=sources.length===1?sources[0]:null
 const partial=source?.quantity&&source.allocated_quantity&&profitPreview(source.quantity,source.allocated_quantity)!=='0.00000000'
 const mmk=(v?:string|null)=>v==null?'Not yet available':`${amount(v)} MMK`
 const stages=[
  {title:'Original purchase',value:source?`${amount(source.amount)} ${source.currency}`:sources.length?`${sources.length} purchase lines`:'Source not linked',hint:partial?'Full source line; allocated share below':sources.length>1?'Each historical currency retained':'Historical source amount'},
  {title:'Exchange rate',value:source?`1 ${source.currency} = ${amount(source.rate)} MMK`:sources.length?'Multiple historical rates':'Not yet available',hint:'Transaction rate · preserved'},
  {title:'Converted purchase',value:mmk(converted),hint:partial||sources.length>1?'Assigned MMK purchase cost':'Purchase cost in MMK'},
  {title:'Transportation',value:mmk(transport),hint:'Transport + loading + unloading'},
  {title:'Other costs',value:mmk(other),hint:'Active shipment expenses'},
  {title:'Landed cost',value:mmk(landed),hint:finalized?'Finalized historical cost':'Calculate and review before finalizing',accent:true},
  {title:'Selling price',value:canEstimate&&selling?(profit===null?'Enter a valid amount':mmk(selling)):'Not recorded',hint:canEstimate&&selling?'Scenario · same quantity as costs':'Use the optional scenario below'},
  {title:profit?.startsWith('-')?'Loss':'Profit',value:!canPreviewProfit?'Restricted':profit===null?'Not yet available':mmk(profit),hint:profit!==null?'Estimated gross profit · not a sale':'Requires landed cost and selling price',profit:true},
 ]
 return <motion.section aria-label="Cost journey" initial={reduced?false:{opacity:0,y:4}} animate={{opacity:1,y:0}} transition={{duration:0.15}} className="panel min-w-0 overflow-hidden">
 <div className="flex flex-wrap items-center justify-between gap-3 border-b px-4 py-3"><div className="flex min-w-0 items-center gap-3"><span className="relative rounded-lg bg-primary/5 p-2 text-primary"><Route className="size-4"/><span className="absolute -bottom-0.5 -right-0.5 size-2 rounded-full bg-brand-yellow"/></span><div className="min-w-0"><h3 className="text-[10px] font-bold uppercase tracking-[0.18em]">Pwint Thit / Cost journey</h3><p className="mt-1 break-words text-xs text-muted-foreground">{scope}</p></div></div><StatusBadge tone={finalized?'success':'warning'}>{examplePrice?'Illustrative example':finalized?'Finalized':'Preview'}</StatusBadge></div>
 <ol className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4">{stages.map((s,i)=><li key={i} className={`relative min-w-0 border-b px-4 py-3 sm:border-r sm:p-4 ${s.accent?'bg-primary/5':s.profit&&profit?.startsWith('-')?'bg-red-50':''}`}><div className="mb-2 flex items-center gap-2"><span aria-hidden="true" className={`flex size-5 shrink-0 items-center justify-center rounded-full text-[9px] font-bold ${s.accent?'bg-primary text-white':'bg-muted text-muted-foreground'}`}>{String(i+1).padStart(2,'0')}</span><span className="text-[11px] font-medium text-muted-foreground">{s.title}</span>{i<7&&<><ArrowRight aria-hidden="true" className="ml-auto hidden size-3 text-border sm:block"/><ArrowDown aria-hidden="true" className="ml-auto size-3 text-border sm:hidden"/></>}</div><p data-testid={s.accent?'landed-total':s.profit?'journey-profit':undefined} aria-live={s.profit?'polite':undefined} className={`break-words text-sm font-semibold tabular-nums ${s.accent?'text-primary':s.profit&&profit?.startsWith('-')?'text-red-800':''}`}>{s.value}</p><p className="mt-1 text-[10px] leading-4 text-muted-foreground">{s.hint}</p></li>)}</ol>
 {sources.length>0&&<details className="border-b px-4 py-3 text-xs"><summary className="cursor-pointer font-medium">Purchase sources{partial?' · partial allocation':''}</summary><ul className="mt-3 space-y-2">{sources.map((s,i)=><li key={i} className="break-words leading-5 text-muted-foreground">{s.reference} · {amount(s.amount)} {s.currency} · 1 {s.currency} = {amount(s.rate)} MMK{s.quantity&&s.allocated_quantity&&<span> · {amount(s.allocated_quantity)} of {amount(s.quantity)} base units allocated</span>}</li>)}</ul><p className="mt-2 text-[10px] text-muted-foreground">Source amounts describe full purchase records or lines. Where quantities are shown, converted purchase reflects the allocated share, including preserved rounding.</p></details>}
 {canEstimate&&<details open={!!examplePrice} className="px-4 py-3 text-xs"><summary className="cursor-pointer font-medium">Selling price & profit scenario</summary><div className="mt-3 grid grid-cols-1 items-end gap-3 sm:grid-cols-2"><FormField label="Scenario selling price (MMK)" hint="Total selling value for the same quantity as this journey.">{p=><CurrencyInput {...p} value={selling} onValueChange={setSelling}/>}</FormField><p className="text-[11px] leading-5 text-muted-foreground">Selling value − landed cost = estimated gross profit. This scenario does not save prices or record a sale.</p></div></details>}
 {notes&&<p className="border-t px-4 py-3 text-xs leading-5 text-muted-foreground">{notes}</p>}
 </motion.section>
}
