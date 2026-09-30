import { useState, type FormEvent } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { PageHeader, FormField, DataTable } from '@/components/shared'
import { DecimalInput } from '@/components/shared/decimal-input'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import { amount, today, type Currency, type Rate } from './types'
const quoteTime = () => new Date(Date.now() + 390 * 60000).toISOString().slice(11, 23)
export default function CurrencySettings({ current }: { current: CurrentUser }) {
 const client = useQueryClient()
 const [currency, setCurrency] = useState('INR')
 const [date, setDate] = useState(today)
 const [time, setTime] = useState(quoteTime)
 const [value, setValue] = useState('')
 const [foreign, setForeign] = useState('1')
 const [source, setSource] = useState('')
 const [notice, setNotice] = useState('')
 const currencies = useQuery({ queryKey: ['currencies'], queryFn: ({ signal }) => requestJSON<Currency[]>('/currencies', { signal }) })
 const history = useQuery({ queryKey: ['rate-history', currency], queryFn: ({ signal }) => requestJSON<Rate[]>(`/exchange-rates?currency=${currency}&as_of=9999-12-31T23%3A59%3A59Z`, { signal }) })
 const save = useMutation({ mutationFn: () => requestJSON('/exchange-rates', { method: 'POST', body: JSON.stringify({ currency_code: currency, foreign_amount: foreign, mmk_amount: value, effective_at: `${date}T${time.length === 5 ? `${time}:00` : time}+06:30`, source }) }), onSuccess: () => { setNotice('Exchange rate saved. Existing purchases are unchanged.'); setTime(quoteTime()); setValue(currency === 'MMK' ? '1' : ''); void client.invalidateQueries({ queryKey: ['rate-history'] }); void client.invalidateQueries({ queryKey: ['rates'] }) } })
 const addCurrency = useMutation({ mutationFn: (data: object) => requestJSON('/currencies', { method: 'POST', body: JSON.stringify(data) }), onSuccess: () => { setNotice('Currency added.'); void client.invalidateQueries({ queryKey: ['currencies'] }) } })
 function submit(e: FormEvent) { e.preventDefault(); if (!save.isPending) save.mutate() }
 return <><PageHeader eyebrow="Purchasing / Setup" title="Currencies & exchange rates" description="MMK is the base currency. Enter the quoted amounts, for example 100 INR = 4,450 MMK. Save a new quote whenever the rate changes." actions={<Button asChild variant="outline"><a href="/purchases">Purchases</a></Button>} />
 {notice && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">{notice}</p>}
 <section className="panel mb-6 p-5"><h2 className="mb-5 text-sm font-semibold">Record an exchange rate</h2><form onSubmit={submit} className="grid gap-5 sm:grid-cols-2"><FormField label="Rate currency" required>{p => <Select {...p} value={currency} onValueChange={v => { setCurrency(v); setForeign('1'); setValue(v === 'MMK' ? '1' : '') }}>{(currencies.data || []).map(c => <SelectItem key={c.code} value={c.code}>{c.code} · {c.name}</SelectItem>)}</Select>}</FormField><FormField label="Effective date" required>{p => <input {...p} type="date" className="field" value={date} onChange={e => setDate(e.target.value)} />}</FormField><FormField label="Effective time" required hint="Myanmar time. Use a different time for each new quote on the same day.">{p => <input {...p} type="time" step="0.001" className="field" value={time} onChange={e => setTime(e.target.value)} />}</FormField><FormField label="Foreign currency amount" required hint={`For example, enter 100 for a quote per 100 ${currency}.`}>{p => <DecimalInput {...p} scale={10} integerDigits={14} suffix={currency} value={foreign} readOnly={currency === 'MMK'} onValueChange={setForeign} />}</FormField><FormField label="Exchange rate" required hint={currency === 'MMK' ? 'Fixed at 1: MMK is the base currency.' : `MMK paid for ${foreign || "…"} ${currency}. Both amounts can be changed before saving.`}>{p => <DecimalInput {...p} scale={10} integerDigits={14} suffix="MMK" value={value} readOnly={currency === 'MMK'} onValueChange={setValue} />}</FormField><FormField label="Rate source" required>{p => <input {...p} className="field" maxLength={500} value={source} onChange={e => setSource(e.target.value)} placeholder="Bank or supplier quote reference" />}</FormField>{save.error && <p role="alert" className="text-sm text-destructive">{save.error.message}</p>}<div className="sm:col-span-2"><Button disabled={save.isPending}>Save new rate</Button></div></form></section>
 <DataTable caption="Exchange-rate history" rows={history.data || []} rowKey={r => r.id} loading={history.isPending} error={history.error?.message || currencies.error?.message} onRetry={() => { void history.refetch(); void currencies.refetch() }} columns={[{id:'date',header:'Effective date & time',cell:r=>new Date(r.effective_at).toLocaleString('en-GB', { timeZone: 'Asia/Yangon' })},{id:'rate',header:'MMK per unit',cell:r=>`${amount(r.mmk_per_unit)} MMK / ${r.currency_code}`},{id:'source',header:'Source',cell:r=>r.source}]} />
 {can(current,permissions.settingsManage) && <section className="panel mt-6 p-5"><h2 className="mb-5 text-sm font-semibold">Add another currency</h2><form className="grid gap-4 sm:grid-cols-3" onSubmit={e => { e.preventDefault(); const data = new FormData(e.currentTarget); if (!addCurrency.isPending) addCurrency.mutate({ code:data.get('code'),name:data.get('name'),minor_units:2 }) }}><FormField label="Currency code" required>{p=><input {...p} name="code" className="field uppercase" maxLength={3} pattern="[A-Za-z]{3}" placeholder="EUR" />}</FormField><FormField label="Currency name" required>{p=><input {...p} name="name" className="field" maxLength={100} placeholder="Euro" />}</FormField><Button className="self-end" disabled={addCurrency.isPending}>Add currency</Button>{addCurrency.error&&<p role="alert" className="text-sm text-destructive">{addCurrency.error.message}</p>}</form></section>}
 </>
}
