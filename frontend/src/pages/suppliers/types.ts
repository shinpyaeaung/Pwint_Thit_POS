export type SupplierInput = {
  code: string; name: string; contact_person: string; phone: string; address: string;
  country_code: string; supplier_type: string; payment_terms: string; notes: string;
  is_active: boolean; version: string;
}
export type Supplier = Omit<SupplierInput, 'contact_person' | 'phone' | 'address' | 'country_code' | 'supplier_type' | 'payment_terms' | 'notes'> & {
  id: string; contact_person: string | null; phone: string | null; address: string | null;
  country_code: string | null; supplier_type: string | null; payment_terms: string | null; notes: string | null;
  archived_at: string | null; created_at: string; updated_at: string;
}
export type Purchase = {
  id: string; purchase_number: string; supplier_invoice_number: string | null;
  purchased_at: string; due_date: string | null; status: string; currency_code: string;
  item_count: number; total_original?: string;
}
export type History = { total: number; can_view_cost: boolean; purchases: Purchase[] }
