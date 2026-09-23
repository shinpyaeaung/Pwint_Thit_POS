import { DecimalInput, type DecimalInputProps } from './decimal-input'
export function QuantityInput({ unit = 'units', ...props }: Omit<DecimalInputProps, 'suffix'> & { unit?: string }) {
  return <DecimalInput scale={6} integerDigits={14} {...props} suffix={unit} />
}
