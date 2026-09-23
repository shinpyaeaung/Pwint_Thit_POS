export type Lookup = { id: string; name: string; is_active: boolean }
export type Unit = { code: string; name: string }
export type Catalog = { categories: Lookup[]; brands: Lookup[]; units: Unit[] }
export type Packaging = { unit_code: string; units_per_pack: string; barcode: string | null; is_default_purchase: boolean; is_default_sale: boolean }
export type ProductInput = { sku: string; name: string; barcode: string; category_id: string; brand_id: string; country_code: string; description: string; base_unit_code: string; minimum_stock: string; tracks_expiry: boolean; is_active: boolean; version: string; packaging: Packaging[] }
export type Product = Omit<ProductInput, 'barcode' | 'category_id' | 'brand_id' | 'country_code' | 'description' | 'minimum_stock'> & { id: string; barcode: string | null; category_id: string | null; brand_id: string | null; category_name: string | null; brand_name: string | null; country_code: string | null; description: string | null; minimum_stock: string | null; archived_at: string | null; created_at: string; updated_at: string }
export const decimalText = (value: string) => value.includes('.') ? value.replace(/0+$/, '').replace(/\.$/, '') : value
export const unitName = (catalog: Catalog, code: string) => catalog.units.find(u => u.code === code)?.name || code
export function conversion(pack: Packaging, base: string, catalog: Catalog) {
  const name = unitName(catalog, base)
  const plural = name.endsWith('x') ? `${name}es` : `${name}s`
  return `1 ${unitName(catalog, pack.unit_code)} = ${decimalText(pack.units_per_pack)} ${decimalText(pack.units_per_pack) === '1' ? name : plural}`
}
