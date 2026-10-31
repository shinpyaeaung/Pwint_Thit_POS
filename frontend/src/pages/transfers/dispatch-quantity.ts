const scale = 1000000n
function quantity(value: string) {
  if (!/^\d{1,14}(\.\d{1,6})?$/.test(value)) throw new Error('Invalid quantity')
  const [whole, fraction = ''] = value.split('.')
  return BigInt(whole + fraction.padEnd(6, '0'))
}
export function dispatchQuantity(value: string, cartonSize: string | null, loose = '0'): string | null {
  try {
    const size = cartonSize === null ? scale : quantity(cartonSize)
    if (size <= 0n) return null
    const packed = quantity(value) * size
    if (packed % scale !== 0n) return null
    const total = packed / scale + quantity(loose)
    const text = total.toString().padStart(7, '0')
    const result = `${text.slice(0, -6)}.${text.slice(-6)}`
    quantity(result) // Keep the existing API's quantity range.
    return result
  } catch { return null }
}
export function dispatchQuantityError(value: string | null, available: string): string | null {
  try {
    if (value === null || quantity(value) <= 0n) return 'Enter a positive quantity with at most six decimal places.'
    if (quantity(value) > quantity(available)) return 'Dispatch quantity exceeds available stock.'
    return null
  } catch { return 'Enter a valid dispatch quantity.' }
}
