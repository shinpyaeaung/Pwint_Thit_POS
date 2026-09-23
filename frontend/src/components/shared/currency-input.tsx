import { DecimalInput, type DecimalInputProps } from './decimal-input'
export function CurrencyInput({ currency = 'MMK', ...props }: Omit<DecimalInputProps, 'suffix'> & { currency?: string }) {
  return <DecimalInput scale={4} integerDigits={16} {...props} suffix={currency} />
}
