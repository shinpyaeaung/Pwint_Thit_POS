import { useState, type FormEvent } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { PageHeader, FormField, DataTable } from '@/components/shared'
import { DecimalInput } from '@/components/shared/decimal-input'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import { amount, today, type Currency, type Rate } from './types'
export default function CurrencySettings({ current }: { current: CurrentUser }) {
 const client = useQueryClient()
 const [currency, setCurrency] = useState('INR')
 const [date, setDate] = useState(today)
 const [value, setValue] = useState('')
 const [source, setSource] = useState('')
 const [notice, setNotice] = useState('')
 const currencies = useQuery({ queryKey: ['currencies'], queryFn: ({ signal }) => requestJSON<Currency[]>('/currencies', { signal }) })
 const history = useQuery({ queryKey: ['rate-history', currency], queryFn: ({ signal }) => requestJSON<Rate[]>(`/exchange-rates?currency=${currency}&as_of=9999-12-31T23%3A59%3A59Z`, { signal }) })
 const save = useMutation({ mutationFn: () => requestJSON('/exchange-rates', { method: 'POST', body: JSON.stringify({ currency_code: currency, mmk_per_unit: value, effective_at: `${date}T00:00:00+06:30`, source }) }), onSuccess: () => { setNotice('Exchange rate saved. Existing purchases are unchanged.'); setValue(''); void client.invalidateQueries({ queryKey: ['rate-history'] }); void client.invalidateQueries({ queryKey: ['rates'] }) } })
 const addCurrency = useMutation({ mutationFn: (data: object) => requestJSON('/currencies', { method: 'POST', body: JSON.stringify(data) }), onSuccess: () => { setNotice('Currency added.'); void client.invalidateQueries({ queryKey: ['currencies'] }) } })
 function submit(e: FormEvent) { e.preventDefault(); if (!save.isPending) save.mutate() }
 return <><PageHeader eyebrow="Purchasing / Setup" title="Currencies & exchange rates" description="MMK is the base currency. Rates are append-only historical quotes." actions={<Button asChild variant="outline"><a href="/purchases">Purchases</a></Button>} />
 {notice && <p role="status" className="mb-5 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">{notice}</p>}
 <section className="panel mb-6 p-5"><h2 className="mb-5 text-sm font-semibold">Record an exchange rate</h2><form onSubmit={submit} className="grid gap-5 sm:grid-cols-2"><FormField label="Rate currency" required>{p => <Select {...p} value={currency} onValueChange={v => { setCurrency(v); setValue(v === 'MMK' ? '1' : '') }}>{(currencies.data || []).map(c => <SelectItem key={c.code} value={c.code}>{c.code} · {c.name}</SelectItem>)}</Select>}</FormField><FormField label="Effective date" required>{p => <input {...p} type="date" className="field" value={date} onChange={e => setDate(e.target.value)} />}</FormField><FormField label="Exchange rate" required hint={`MMK per 1 ${currency}`}>{p => <DecimalInput {...p} scale={10} integerDigits={14} suffix="MMK" value={value} readOnly={currency === 'MMK'} onValueChange={setValue} />}</FormField><FormField label="Rate source" required>{p => <input {...p} className="field" maxLength={500} value={source} onChange={e => setSource(e.target.value)} placeholder="Bank or supplier quote reference" />}</FormField>{save.error && <p role="alert" className="text-sm text-destructive">{save.error.message}</p>}<div className="sm:col-span-2"><Button disabled={save.isPending}>Save new rate</Button></div></form></section>
 <DataTable caption="Exchange-rate history" rows={history.data || []} rowKey={r => r.id} loading={history.isPending} error={history.error?.message || currencies.error?.message} onRetry={() => { void history.refetch(); void currencies.refetch() }} columns={[{id:'date',header:'Effective date',cell:r=>new Date(r.effective_at).toLocaleDateString()},{id:'rate',header:'MMK per unit',cell:r=>`${amount(r.mmk_per_unit)} MMK / ${r.currency_code}`},{id:'source',header:'Source',cell:r=>r.source}]} />
 {can(current,permissions.settingsManage) && <section className="panel mt-6 p-5"><h2 className="mb-5 text-sm font-semibold">Add another currency</h2><form className="grid gap-4 sm:grid-cols-3" onSubmit={e => { e.preventDefault(); const data = new FormData(e.currentTarget); if (!addCurrency.isPending) addCurrency.mutate({ code:data.get('code'),name:data.get('name'),minor_units:2 }) }}><FormField label="Currency code" required>{p=><input {...p} name="code" className="field uppercase" maxLength={3} pattern="[A-Za-z]{3}" placeholder="EUR" />}</FormField><FormField label="Currency name" required>{p=><input {...p} name="name" className="field" maxLength={100} placeholder="Euro" />}</FormField><Button className="self-end" disabled={addCurrency.isPending}>Add currency</Button>{addCurrency.error&&<p role="alert" className="text-sm text-destructive">{addCurrency.error.message}</p>}</form></section>}
 </>
}
