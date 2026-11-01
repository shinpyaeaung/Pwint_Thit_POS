import { useState, type ComponentProps } from 'react'
import { cn } from '@/lib/utils'
export type DecimalInputProps = Omit<ComponentProps<'input'>, 'type' | 'value' | 'defaultValue' | 'onChange' | 'pattern' | 'step' | 'min' | 'max'> & { value: string; onValueChange: (value: string) => void; scale?: number; integerDigits?: number; allowNegative?: boolean; suffix?: string; preserveTrailingZeros?: boolean }
// Text throughout: financial amounts never pass through Number or parseFloat.
export function DecimalInput({ value, onValueChange, scale = 4, integerDigits = 16, allowNegative = false, suffix, className, preserveTrailingZeros = false, ...props }: DecimalInputProps) {
  const [draft, setDraft] = useState<string | null>(null)
  const display = preserveTrailingZeros || draft === value ? value : value.replace(/(\.\d*?[1-9])0+$|\.0+$/, '$1')
  const pattern = `${allowNegative ? '-?' : ''}[0-9]{1,${integerDigits}}${scale ? `(\\.[0-9]{1,${scale}})?` : ''}`
  const invalid = value !== '' && !new RegExp(`^${pattern}$`).test(value)
  return <div className="relative"><input {...props} type="text" inputMode="decimal" value={display} onBlur={e => { setDraft(null); props.onBlur?.(e) }} pattern={pattern} title={`Use up to ${integerDigits} whole digits and ${scale} decimal places${allowNegative ? '' : ', without a minus sign'}.`} aria-invalid={props['aria-invalid'] || invalid || undefined} onChange={e => { setDraft(e.target.value); onValueChange(e.target.value) }} className={cn('field text-right tabular-nums read-only:bg-muted read-only:text-muted-foreground read-only:cursor-default', suffix && 'pr-20', className)} />{suffix && <span aria-hidden="true" className="pointer-events-none absolute right-3 top-3 text-xs text-muted-foreground">{suffix}</span>}</div>
}
