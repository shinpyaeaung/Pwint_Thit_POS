import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { FormField, Modal } from '@/components/shared'
import { DecimalInput } from '@/components/shared/decimal-input'
import { requestJSON, ApiError } from '@/services/api'
import { amount } from '../purchases/types'
import { cartonCost, type Stock } from './types'

type Correction = { id: string; old_batch: string; new_batch: string; old_unit_cost_mmk: string; new_unit_cost_mmk: string; reason: string; corrected_at: string; recorded_by: string }
const zero = (value: string) => /^0(?:\.0+)?$/.test(value)
export function ManualCostCorrection({ stock, close }: { stock: Stock; close: () => void }) {
  const client = useQueryClient()
  const [request] = useState(() => crypto.randomUUID())
  const [cost, setCost] = useState(''), [reason, setReason] = useState('')
  const history = useQuery({ queryKey: ['manual-cost-history', stock.batch_id, stock.warehouse_id], queryFn: () => requestJSON<Correction[]>(`/inventory/manual-stock/cost-corrections?batch_id=${stock.batch_id}&warehouse_id=${stock.warehouse_id}`) })
  const save = useMutation({ mutationFn: () => requestJSON('/inventory/manual-stock/cost-corrections', { method: 'POST', body: JSON.stringify({ request_id: request, batch_id: stock.batch_id, warehouse_id: stock.warehouse_id, version: stock.version, unit_cost_mmk: cost, reason }) }), onSuccess: async () => { await client.invalidateQueries(); close() } })
  const uncertain = save.error instanceof ApiError && (save.error.status === 0 || save.error.status >= 500)
  const locked = save.isPending || uncertain
  const blocked = !zero(stock.reserved_quantity) ? 'Release reserved stock before correcting its cost.' : zero(stock.sellable_quantity) && zero(stock.damaged_quantity) ? 'This batch has no remaining stock to correct.' : ''
  const valid = /^[0-9]{1,14}(\.[0-9]{1,4})?$/.test(cost) && !!reason.trim() && !blocked
  return <Modal open title="Correct landed cost" description={`${stock.product_name} · ${stock.batch_number} · ${stock.warehouse_name}`} busy={locked} onOpenChange={open => { if (!open && !locked) close() }}>
    <form className="space-y-4" onSubmit={e => { e.preventDefault(); if (valid && !save.isPending) save.mutate() }}>
      <p className="text-sm">This corrects remaining stock only. Completed sales, past profit and original stock records keep their recorded costs. A new batch and dated correction movements preserve the history.</p>
      <div className="rounded-lg border bg-muted p-3 text-sm"><p>Current landed cost: <strong>{amount(stock.unit_cost_mmk)} MMK / {stock.base_unit}</strong></p><p>Remaining: {amount(stock.sellable_quantity)} sellable · {amount(stock.damaged_quantity)} damaged · {amount(stock.reserved_quantity)} reserved {stock.base_unit}</p></div>
      {blocked && <p role="alert" className="text-sm text-destructive">{blocked}</p>}
      <fieldset disabled={locked || !!blocked} className="min-w-0 space-y-4">
        <FormField label={`Correct landed cost per ${stock.base_unit} (MMK)`} required hint="Cost for one individual stock unit, including transport. Enter 0 only for free stock.">{props => <DecimalInput {...props} scale={4} integerDigits={14} suffix="MMK" value={cost} onValueChange={setCost}/>}</FormField>
        {stock.carton_size && cost && <p className="text-xs text-muted-foreground">Equivalent per carton ({amount(stock.carton_size)} {stock.base_unit}): {amount(cartonCost(cost, stock.carton_size))} MMK</p>}
        <FormField label="Cost correction reason" required>{props => <textarea {...props} className="field min-h-20" value={reason} maxLength={2000} onChange={e => setReason(e.target.value)}/>}</FormField>
        <p className="text-xs text-muted-foreground">Stock quantities, expiry, carton size and warehouse selling prices stay the same. Future sales of the corrected stock use its new cost.</p>
      </fieldset>
      {save.error && <p role="alert" className="text-sm text-destructive">{save.error.message}{uncertain && ' Retry the same correction to confirm its result.'}</p>}
      <Button disabled={!valid || save.isPending}>{save.isPending ? 'Saving correction…' : uncertain ? 'Retry same cost correction' : 'Confirm cost correction'}</Button>
    </form>
    <section className="mt-5 space-y-3 border-t pt-4"><h3 className="text-sm font-semibold">Cost correction history</h3>{history.isPending && <p className="text-sm">Loading history…</p>}{history.error && <p role="alert">{history.error.message}</p>}{history.data?.length === 0 && <p className="text-xs text-muted-foreground">No previous cost corrections for this batch.</p>}{history.data?.map(row => <div key={row.id} className="space-y-1 rounded-lg border p-3 text-xs"><p>{amount(row.old_unit_cost_mmk)} → {amount(row.new_unit_cost_mmk)} MMK / {stock.base_unit}</p><p>{row.old_batch} → {row.new_batch}</p><p>{row.reason}</p><p className="text-muted-foreground">{new Date(row.corrected_at).toLocaleString()} · {row.recorded_by}</p></div>)}</section>
  </Modal>
}
