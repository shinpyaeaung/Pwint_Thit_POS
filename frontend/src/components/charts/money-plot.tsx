import { Bar, BarChart, CartesianGrid, Cell, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { amount } from '@/pages/purchases/types'
import type { ChartDatum } from './chart-data'
const compact = new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 })
export default function MoneyPlot({ data }: { data: ChartDatum[] }) {
  return <div className="min-w-0 overflow-hidden" style={{ height: Math.max(150, data.length * 38 + 40) }}>
    <ResponsiveContainer width="100%" height="100%" minWidth={0}>
      <BarChart data={data} layout="vertical" margin={{ top: 4, right: 16, bottom: 4, left: 0 }} accessibilityLayer>
        <CartesianGrid horizontal={false} stroke="var(--border)" strokeDasharray="3 3"/>
        <XAxis minTickGap={24} type="number" tickFormatter={value=>compact.format(value)} tick={{fontSize:12,fill:'var(--muted-foreground)'}} axisLine={false} tickLine={false} domain={data.every(row=>row.geometry===0)?[-1,1]:['auto','auto']}/>
        <YAxis type="category" dataKey="label" width={128} tick={({x,y,payload})=><text x={Number(x)-8} y={y} textAnchor="end" dominantBaseline="middle" fontSize={12} fill="var(--foreground)">{String(payload.value).length>14?`${String(payload.value).slice(0,13)}…`:String(payload.value)}</text>} axisLine={false} tickLine={false}/>
        <ReferenceLine x={0} stroke="var(--muted-foreground)"/>
        <Tooltip cursor={{fill:'var(--muted)'}} content={({active,payload})=>{
          const row=payload?.[0]?.payload as ChartDatum|undefined
          return active&&row?<div className="max-w-64 rounded-md border bg-surface p-3 text-xs shadow-lg" role="status"><p className="break-words font-medium">{row.label}</p><p className="mt-1 break-all tabular-nums">{amount(row.exact)} MMK</p></div>:null
        }}/>
        <Bar dataKey="geometry" name="Amount (MMK)" maxBarSize={18} isAnimationActive={false}>{data.map((row,i)=><Cell key={i} stroke={row.accent&&row.geometry>=0?'#946200':undefined} strokeWidth={1} fill={row.geometry<0?'var(--primary)':row.accent?'var(--color-brand-yellow)':'#625c57'}/>)}</Bar>
      </BarChart>
    </ResponsiveContainer>
    <p className="sr-only">Use arrow keys while the chart is focused to inspect amounts, or open Exact chart values below. Axis labels use approximate compact MMK values.</p>
  </div>
}
