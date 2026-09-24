import { useState, type FormEvent } from 'react'
import { useQuery, useMutation } from '@tanstack/react-query'
import { Plus, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select, SelectItem } from '@/components/ui/select'
import { PageHeader, FormField, CurrencyInput, QuantityInput, ConfirmDialog, EmptyState } from '@/components/shared'
import { DecimalInput } from '@/components/shared/decimal-input'
import { requestJSON } from '@/services/api'
import { can, permissions, type CurrentUser } from '@/permissions'
import { amount, preview, today, type Currency, type Rate, type SupplierOption, type ProductOption, type LineInput, type Purchase } from './types'

type Row = LineInput & { product: ProductOption; key: string }
export default function PurchaseForm({ current }: { current: CurrentUser }) {
 const [requestID] = useState(() => crypto.randomUUID())
 const [number, setNumber] = useState('')
 const [date, setDate] = useState(today)
 const [due, setDue] = useState('')
 const [invoice, setInvoice] = useState('')
 const [notes, setNotes] = useState('')
 const [supplierSearch, setSupplierSearch] = useState('')
 const [supplier, setSupplier] = useState<SupplierOption | null>(null)
 const [productSearch, setProductSearch] = useState('')
 const [productID, setProductID] = useState('')
 const [currency, setCurrency] = useState('MMK')
 const [rateID, setRateID] = useState('')
 const [rate, setRate] = useState('1')
 const [rows, setRows] = useState<Row[]>([])
 const [confirm, setConfirm] = useState(false)
 const [validation, setValidation] = useState('')
 const manual = can(current, permissions.exchangeRatesManage)
 const currencies = useQuery({ queryKey: ['currencies'], queryFn: ({ signal }) => requestJSON<Currency[]>('/currencies', { signal }) })
 const suppliers = useQuery({ queryKey: ['purchase-suppliers', supplierSearch], queryFn: ({ signal }) => requestJSON<SupplierOption[]>(`/purchase-options?kind=suppliers&q=${encodeURIComponent(supplierSearch)}`, { signal }) })
 const products = useQuery({ queryKey: ['purchase-products', productSearch], queryFn: ({ signal }) => requestJSON<ProductOption[]>(`/purchase-options?kind=products&q=${encodeURIComponent(productSearch)}`, { signal }) })
 const rates = useQuery({ queryKey: ['rates', currency, date], queryFn: ({ signal }) => requestJSON<Rate[]>(`/exchange-rates?currency=${currency}&as_of=${encodeURIComponent(`${date}T23:59:59+06:30`)}`, { signal }), enabled: currency !== 'MMK' && !!date })
 const lines: LineInput[] = rows.map(({ product_id, unit_code, quantity, units_per_pack, unit_price_original, discount_original, tax_original }) => ({ product_id, unit_code, quantity, units_per_pack, unit_price_original, discount_original, tax_original }))
 const totals = preview(lines, rate)
 const save = useMutation({ mutationFn: () => requestJSON<Purchase>('/purchases', { method: 'POST', body: JSON.stringify({ request_id: requestID, purchase_number: number, supplier_id: supplier?.id, supplier_invoice_number: invoice, purchased_at: `${date}T23:59:59+06:30`, due_date: due, currency_code: currency, exchange_rate_id: rateID, mmk_per_unit: rate, notes, items: lines }) }), onSuccess: p => window.location.assign(`/purchases/${p.id}`) })
 function patch(index: number, patch: Partial<Row>) { setRows(r => r.map((v, i) => i === index ? { ...v, ...patch } : v)) }
 function submit(e: FormEvent) { e.preventDefault(); if (!supplier || !rows.length || !totals || (currency !== 'MMK' && !rateID && !manual)) { setValidation('Choose a supplier, at least one product, and valid amounts and exchange rate.'); return }; setValidation(''); setConfirm(true) }
 if (!can(current, permissions.purchasesViewCost)) return <EmptyState title="Purchase costs restricted" description="Creating a purchase requires purchases.view_cost as well as purchases.create." />
 const supplierOptions = supplier && !suppliers.data?.some(s => s.id === supplier.id) ? [supplier, ...(suppliers.data || [])] : suppliers.data || []
 return <>
  <PageHeader eyebrow="Purchasing / New transaction" title="Create Purchase" description="Record supplier costs in their original currency, with a fixed MMK conversion." actions={<Button variant="outline" asChild><a href="/purchases">Cancel</a></Button>} />
  <form onSubmit={submit} className="space-y-5"><fieldset disabled={save.isPending || confirm} className="min-w-0 space-y-5">
   <section className="panel min-w-0 p-5"><h2 className="mb-5 text-sm font-semibold">Purchase information</h2><div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
    <FormField label="Purchase number" required>{p => <input {...p} className="field" value={number} maxLength={100} onChange={e => setNumber(e.target.value)} placeholder="PO-2026-001" />}</FormField>
    <FormField label="Purchase date" required>{p => <input {...p} type="date" className="field" value={date} onChange={e => { setDate(e.target.value); setRateID(''); if (currency !== 'MMK') setRate('') }} />}</FormField>
    <FormField label="Payment due date">{p => <input {...p} type="date" min={date} className="field" value={due} onChange={e => setDue(e.target.value)} />}</FormField>
    <div className="min-w-0 space-y-2"><FormField label="Find supplier">{p => <input {...p} className="field" placeholder="Search name or code…" value={supplierSearch} onChange={e => setSupplierSearch(e.target.value)} />}</FormField><FormField label="Supplier" required>{p => <Select {...p} value={supplier?.id || ''} onValueChange={id => setSupplier(supplierOptions.find(s => s.id === id) || null)}><SelectItem value="">Choose supplier</SelectItem>{supplierOptions.map(s => <SelectItem key={s.id} value={s.id}>{s.name} · {s.code}</SelectItem>)}</Select>}</FormField></div>
    <FormField label="Supplier invoice number">{p => <input {...p} className="field" value={invoice} maxLength={200} onChange={e => setInvoice(e.target.value)} />}</FormField>
    <FormField label="Currency" required>{p => <Select {...p} value={currency} onValueChange={v => { setCurrency(v); setRateID(''); setRate(v === 'MMK' ? '1' : '') }} >{(currencies.data || []).map(c => <SelectItem key={c.code} value={c.code}>{c.code} · {c.name}</SelectItem>)}</Select>}</FormField>
   </div></section>
   <section className="panel min-w-0 p-5"><h2 className="mb-2 text-sm font-semibold">Transaction exchange rate</h2><p className="mb-5 text-xs text-muted-foreground">This rate stays with the purchase. Adding a future rate never changes it.</p><div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
    {currency !== 'MMK' && <FormField label="Historical quote" hint="Quotes effective on or before the purchase date.">{p => <Select {...p} value={rateID} onValueChange={id => { setRateID(id); setRate(rates.data?.find(r => r.id === id)?.mmk_per_unit || '') }}><SelectItem value="">{manual ? 'Enter custom rate' : 'Choose saved quote'}</SelectItem>{(rates.data || []).map(r => <SelectItem key={r.id} value={r.id}>{amount(r.mmk_per_unit)} MMK · {new Date(r.effective_at).toLocaleDateString()} · {r.source}</SelectItem>)}</Select>}</FormField>}
    <FormField label="MMK per currency unit" required hint={`1 ${currency} = this many MMK`}>{p => <DecimalInput {...p} scale={10} integerDigits={14} suffix="MMK" value={rate} readOnly={currency === 'MMK' || !manual || !!rateID} onValueChange={setRate} />}</FormField>
   </div>{rates.error && <p role="alert" className="mt-3 text-sm text-destructive">{rates.error.message}</p>}</section>
   <section className="panel min-w-0 p-5"><h2 className="mb-4 text-sm font-semibold">Purchase items</h2><div className="mb-5 grid grid-cols-1 items-end gap-3 sm:grid-cols-[1fr_1.5fr_auto]">
    <FormField label="Find product">{p => <input {...p} className="field" placeholder="Search name or SKU…" value={productSearch} onChange={e => { setProductSearch(e.target.value); setProductID('') }} />}</FormField>
    <FormField label="Product to add">{p => <Select {...p} value={productID} onValueChange={setProductID}><SelectItem value="">Choose product</SelectItem>{(products.data || []).filter(p => p.packaging.length).map(p => <SelectItem key={p.id} value={p.id}>{p.name} · {p.sku}</SelectItem>)}</Select>}</FormField>
    <Button type="button" variant="outline" disabled={!productID || rows.length >= 100} onClick={() => { const p = products.data?.find(p => p.id === productID); if (!p) return; const pack = p.packaging.find(p => p.is_default_purchase) || p.packaging[0]; setRows(r => [...r, { key: crypto.randomUUID(), product: p, product_id: p.id, unit_code: pack.unit_code, units_per_pack: pack.units_per_pack, quantity: '1', unit_price_original: '', discount_original: '0', tax_original: '0' }]); setProductID('') }}><Plus />Add item</Button>
   </div>
   {!rows.length && <p className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">Choose a product to start your purchase.</p>}
   <div className="space-y-4">{rows.map((row, i) => <div key={row.key} className="rounded-xl border p-4"><div className="mb-4 flex items-center justify-between gap-3"><div><h3 className="text-sm font-semibold">{row.product.name}</h3><p className="mt-1 text-xs text-muted-foreground">{row.product.sku} · 1 pack = {amount(row.units_per_pack)} base units</p></div><Button type="button" variant="ghost" size="sm" aria-label={`Remove item ${i + 1}`} onClick={() => setRows(r => r.filter(v => v.key !== row.key))}><Trash2 /></Button></div><div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
    <FormField label={`Unit ${i + 1}`} required>{p => <Select {...p} value={row.unit_code} onValueChange={v => { const pack = row.product.packaging.find(p => p.unit_code === v)!; patch(i, { unit_code: v, units_per_pack: pack.units_per_pack, unit_price_original: '' }) }}>{row.product.packaging.map(p => <SelectItem key={p.unit_code} value={p.unit_code}>{p.unit_name}</SelectItem>)}</Select>}</FormField>
    <FormField label={`Quantity ${i + 1}`} required>{p => <QuantityInput {...p} value={row.quantity} onValueChange={v => patch(i, { quantity: v })} />}</FormField>
    <FormField label={`Price per selected unit ${i + 1}`} required>{p => <CurrencyInput {...p} scale={6} integerDigits={14} currency={currency} value={row.unit_price_original} onValueChange={v => patch(i, { unit_price_original: v })} />}</FormField>
    <FormField label={`Line discount ${i + 1}`}>{p => <CurrencyInput {...p} currency={currency} value={row.discount_original} onValueChange={v => patch(i, { discount_original: v })} />}</FormField>
    <FormField label={`Line tax ${i + 1}`}>{p => <CurrencyInput {...p} currency={currency} value={row.tax_original} onValueChange={v => patch(i, { tax_original: v })} />}</FormField>
   </div><p className="mt-4 text-right text-sm font-medium">Line total: {amount(totals?.lines[i])} {currency}</p></div>)}</div></section>
   <div className="grid grid-cols-1 gap-5 lg:grid-cols-2"><section className="panel min-w-0 p-5"><FormField label="Notes">{p => <textarea {...p} className="field min-h-28" maxLength={4000} value={notes} onChange={e => setNotes(e.target.value)} />}</FormField></section><section className="panel min-w-0 border-primary/15 p-5"><p className="text-xs font-medium text-muted-foreground">Purchase conversion preview</p><p data-testid="original-preview" className="mt-3 break-words text-2xl font-semibold tabular-nums">{amount(totals?.original)} {currency}</p><p data-testid="mmk-preview" className="mt-2 break-words text-lg font-semibold tabular-nums text-primary">{amount(totals?.mmk)} MMK</p><p className="mt-3 text-xs leading-5 text-muted-foreground">Original amount × transaction rate. Transportation and landed costs are recorded separately. Posting adds this purchase to the supplier balance; it does not receive stock or record payment.</p></section></div>
  </fieldset>
  {(validation || currencies.error || suppliers.error || products.error) && <p role="alert" className="text-sm text-destructive">{validation || currencies.error?.message || suppliers.error?.message || products.error?.message}</p>}
  <div className="flex justify-end"><Button type="submit" disabled={save.isPending || currencies.isPending}>Review & post purchase</Button></div></form>
  <ConfirmDialog open={confirm} onOpenChange={setConfirm} title="Post this purchase?" description={`${number}: ${amount(totals?.original)} ${currency} = ${amount(totals?.mmk)} MMK. The posted amounts and exchange rate will be locked.`} confirmLabel="Post purchase" busy={save.isPending} error={save.error?.message} onConfirm={() => save.mutate()} />
 </>
}
