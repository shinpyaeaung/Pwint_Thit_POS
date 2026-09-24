export type Shipment = { id:string; shipment_number:string; start_location:string; destination_name:string; status:string; version:string; notes:string|null; expected_arrival_at:string|null; shipped_at:string|null; arrived_at:string|null; costs_finalized_at:string|null; can_view_cost:boolean; transport_total_mmk?:string; expense_total_mmk?:string; last_destination:string|null }
export type Stage = { id:string; stage_number:number; start_location:string; destination:string; provider_name:string; transportation_type:string|null; vehicle_information:string|null; departed_at:string|null; arrived_at:string|null; notes:string|null; transportation_fee_mmk?:string; loading_fee_mmk?:string; unloading_fee_mmk?:string; other_fee_mmk?:string; total_mmk?:string; payment_status:string }
export type Expense = { id:string; category:string; description:string; currency_code:string; amount_original?:string; mmk_per_unit?:string; amount_mmk?:string; incurred_at:string; notes:string|null; voided_at:string|null; void_reason:string|null; payment_status:string }
export type Choice = { id:string; purchase_number:string; supplier_name:string; product_name:string; sku:string; available_quantity:string }
export const iso = (v:string) => v ? new Date(v).toISOString() : ''
export const localDate = (v?:string|null) => { if (!v) return ''; const d=new Date(v); return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16) }
export const dateLabel = (v?:string|null) => v ? new Date(v).toLocaleString() : 'Not set'
export const label = (v:string) => v.replaceAll('_',' ')
