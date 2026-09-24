import { useQuery } from '@tanstack/react-query'
import { requestJSON } from '@/services/api'
import { DataTable, LoadingState } from '@/components/shared'
import { amount } from './types'
type Balance = { total_outstanding_mmk: string; currencies: { currency_code: string; outstanding_original: string; outstanding_mmk: string; amount_paid_mmk: string; purchase_count: number }[] }
export function SupplierBalance({ id }: { id: string }) {
 const q = useQuery({ queryKey: ['supplier-balance', id], queryFn: ({ signal }) => requestJSON<Balance>(`/suppliers/${id}/balance`, { signal }), retry: false })
 if (q.isPending) return <LoadingState label="Loading supplier balance…" />
 return <section className="mt-6"><h2 className="mb-2 text-sm font-semibold">Supplier balance</h2>{q.data && <p className="mb-4 text-xl font-semibold tabular-nums">{amount(q.data.total_outstanding_mmk)} MMK outstanding</p>}<DataTable caption="Balances by currency" rows={q.data?.currencies || []} rowKey={r => r.currency_code} error={q.error?.message} onRetry={() => void q.refetch()} columns={[{ id:'currency', header:'Currency', cell:r=>r.currency_code },{ id:'original', header:'Outstanding original', cell:r=>amount(r.outstanding_original) },{ id:'mmk', header:'Outstanding MMK', cell:r=>amount(r.outstanding_mmk) }]} /><p className="mt-3 text-xs text-muted-foreground">Posted purchases less posted payments and return credits, at their original transaction rates.</p></section>
}
