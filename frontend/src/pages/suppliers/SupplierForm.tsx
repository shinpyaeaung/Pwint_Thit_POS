import { Select, SelectItem } from '@/components/ui/select'
import { useState, type FormEvent } from 'react'
import { useMutation } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { FormField, PageHeader } from '@/components/shared'
import { requestJSON } from '@/services/api'
import type { Supplier, SupplierInput } from './types'

export function SupplierForm({ supplier }: { supplier?: Supplier }) {
  const [form, setForm] = useState<SupplierInput>({
    code: supplier?.code || '', name: supplier?.name || '', contact_person: supplier?.contact_person || '',
    phone: supplier?.phone || '', address: supplier?.address || '', country_code: supplier?.country_code || '',
    supplier_type: supplier?.supplier_type || '', payment_terms: supplier?.payment_terms || '', notes: supplier?.notes || '',
    is_active: supplier?.is_active ?? true, version: supplier?.version || '',
  })
  const back = supplier ? `/suppliers/${supplier.id}` : '/suppliers'
  const save = useMutation({
    mutationFn: () => requestJSON<Supplier>(supplier ? back : '/suppliers', { method: supplier ? 'PUT' : 'POST', body: JSON.stringify(form) }),
    onSuccess: s => window.location.assign(`/suppliers/${s.id}`),
  })
  function set<K extends keyof SupplierInput>(key: K, value: SupplierInput[K]) { setForm(f => ({ ...f, [key]: value })) }
  function submit(e: FormEvent) { e.preventDefault(); if (!save.isPending) save.mutate() }
  const fields = [
    { key: 'name', label: 'Supplier name', limit: 200, required: true },
    { key: 'code', label: 'Supplier code', limit: 100, required: true, hint: 'Unique code, for example SUP-001. Case-insensitive.' },
    { key: 'contact_person', label: 'Contact person', limit: 200 },
    { key: 'phone', label: 'Phone number', limit: 100 },
    { key: 'country_code', label: 'Country', limit: 2, hint: 'Two-letter country code, e.g. MM, IN, TH or CN.' },
    { key: 'supplier_type', label: 'Supplier type', limit: 100, hint: 'For example, manufacturer or wholesaler.' },
  ] as const
  return <>
    <PageHeader eyebrow="Purchasing / Suppliers" title={supplier ? 'Edit Supplier' : 'Add Supplier'} description="Keep purchasing contacts and agreed payment terms in one place." />
    <form onSubmit={submit} className="space-y-5">
      <fieldset disabled={save.isPending} className="space-y-5">
        <section className="panel p-5">
          <h2 className="mb-5 text-sm font-semibold">Supplier & contact details</h2>
          <div className="grid gap-5 sm:grid-cols-2">
            {fields.map(field => <FormField key={field.key} label={field.label} required={'required' in field && field.required} hint={'hint' in field ? field.hint : undefined}>
              {p => <input {...p} className="field" type={field.key === 'phone' ? 'tel' : 'text'} maxLength={field.limit} pattern={field.key === 'country_code' ? '[A-Za-z]{2}' : undefined} value={form[field.key]} onChange={e => set(field.key, field.key === 'country_code' ? e.target.value.toUpperCase() : e.target.value)} />}
            </FormField>)}
          </div>
          <div className="mt-5"><FormField label="Address">{p => <textarea {...p} className="field min-h-24" maxLength={2000} value={form.address} onChange={e => set('address', e.target.value)} />}</FormField></div>
        </section>
        <section className="panel p-5">
          <h2 className="mb-5 text-sm font-semibold">Trading details</h2>
          <div className="grid gap-5 sm:grid-cols-2">
            <FormField label="Payment terms" hint="Record the agreement, e.g. payment within 30 days of invoice.">{p => <textarea {...p} className="field min-h-28" maxLength={2000} value={form.payment_terms} onChange={e => set('payment_terms', e.target.value)} />}</FormField>
            <FormField label="Notes">{p => <textarea {...p} className="field min-h-28" maxLength={4000} value={form.notes} onChange={e => set('notes', e.target.value)} />}</FormField>
            <FormField label="Status" required>{p => <Select {...p}  value={form.is_active ? 'active' : 'inactive'} onValueChange={value => set('is_active', value === 'active')}><SelectItem value="active">Active</SelectItem><SelectItem value="inactive">Inactive</SelectItem></Select>}</FormField>
          </div>
        </section>
      </fieldset>
      {save.error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-destructive">{save.error.message} {supplier && <a className="underline" href={window.location.pathname}>Reload supplier</a>}</p>}
      <div className="flex justify-end gap-3"><Button asChild variant="outline"><a href={back}>Cancel</a></Button><Button type="submit" disabled={save.isPending}>{save.isPending ? 'Saving…' : supplier ? 'Save changes' : 'Create supplier'}</Button></div>
    </form>
  </>
}
