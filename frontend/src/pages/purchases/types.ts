export type Currency = { code: string; name: string; minor_units: number }
export type Rate = { id: string; currency_code: string; mmk_per_unit: string; effective_at: string; source: string }
export type SupplierOption = { id: string; name: string; code: string }
export type Pack = { unit_code: string; unit_name: string; units_per_pack: string; is_default_purchase: boolean }
export type ProductOption = { id: string; name: string; sku: string; packaging: Pack[] }
export type LineInput = { product_id: string; unit_code: string; quantity: string; units_per_pack: string; unit_price_original: string; discount_original: string; tax_original: string }
export type Purchase = {
 id: string; purchase_number: string; supplier_id: string; supplier_name: string; supplier_invoice_number: string | null;
 purchased_at: string; due_date: string | null; status: string; currency_code: string; notes: string | null; can_view_cost: boolean;
 mmk_per_unit?: string; exchange_rate_id?: string | null; total_original?: string; total_mmk?: string;
 amount_paid_mmk?: string | null; outstanding_original?: string | null; outstanding_mmk?: string | null; payment_status?: string | null;
 items?: (Omit<LineInput, 'unit_price_original' | 'discount_original' | 'tax_original'> & { id: string; product_name: string; sku: string; unit_name: string; base_quantity: string; unit_price_original?: string; discount_original?: string; tax_original?: string; total_original?: string })[];
}
// Exact fixed-point arithmetic. Match PostgreSQL's per-line NUMERIC rounding, then convert the summed original total.
function scaled(value: string, scale: number): bigint {
 if (!/^\d{1,16}(\.\d+)?$/.test(value)) throw new Error('Enter decimal values')
 const [whole, fraction = ''] = value.split('.')
 if (fraction.length > scale) throw new Error('Too many decimal places')
 return BigInt(whole + fraction.padEnd(scale, '0'))
}
function rounded(value: bigint, divisor: bigint) { if (value < 0n) throw new Error('Discount exceeds line value'); return (value + divisor / 2n) / divisor }
function fixed(value: bigint) { const s = value.toString().padStart(5, '0'); return `${s.slice(0, -4)}.${s.slice(-4)}` }
export function preview(lines: LineInput[], rate: string) {
 try {
  const totals = lines.map(l => {
   const gross = scaled(l.quantity, 6) * scaled(l.unit_price_original, 6)
   const discount = scaled(l.discount_original || '0', 4) * 100000000n
   if (discount > gross) throw new Error('Discount exceeds line value')
   return rounded(gross - discount + scaled(l.tax_original || '0', 4) * 100000000n, 100000000n)
  })
  const total = totals.reduce((a, b) => a + b, 0n)
  return { original: fixed(total), mmk: fixed(rounded(total * scaled(rate, 10), 10000000000n)), lines: totals.map(fixed) }
 } catch { return null }
}
export function amount(value?: string | null) { if (value == null) return '—'; const [whole, fraction] = value.split('.'); const tail = fraction?.replace(/0+$/, ''); return whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (tail ? `.${tail}` : '') }
export const today = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` }
