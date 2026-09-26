import { amount } from '../purchases/types'
export type ProfitSummary={from:string;to:string;sales_mmk:string;returns_mmk:string;revenue_mmk:string;cogs_mmk:string;expenses_mmk:string;gross_profit_mmk:string|null;net_profit_mmk:string|null;incomplete_cost_sales:number}
export const mmk=(v:string|null)=>v===null?'Unavailable':`${amount(v)} MMK`
