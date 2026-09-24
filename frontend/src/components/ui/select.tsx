import type { ComponentProps, ReactNode } from 'react'
import * as SelectPrimitive from '@radix-ui/react-select'
import { Check, ChevronDown, ChevronUp } from 'lucide-react'
import { cn } from '@/lib/utils'

type SelectProps = Pick<ComponentProps<typeof SelectPrimitive.Trigger>, 'id' | 'aria-label' | 'aria-describedby' | 'aria-invalid' | 'className'> & {
  value: string | number
  onValueChange: (value: string) => void
  disabled?: boolean
  required?: boolean
  children: ReactNode
}
// Ignore the native form bridge’s transient empty value when asynchronous options change.
// Encode all values so optional "All"/"Not assigned" choices can round-trip empty strings.
const encode = (value: string | number) => `option:${value}`
export function Select({ value, onValueChange, disabled, required, children, className, ...props }: SelectProps) {
  return <SelectPrimitive.Root value={encode(value)} onValueChange={v => { if (v.startsWith('option:')) onValueChange(v.slice(7)) }} disabled={disabled} required={required}>
    <SelectPrimitive.Trigger {...props} className={cn('group inline-flex h-10 w-full min-w-0 items-center justify-between gap-3 rounded-lg border border-input bg-white px-3 text-left text-[13px] font-normal text-foreground shadow-xs outline-none transition-colors hover:border-neutral-400 focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-primary/15 data-[state=open]:border-primary data-[state=open]:ring-2 data-[state=open]:ring-primary/10 disabled:cursor-not-allowed disabled:bg-muted disabled:text-muted-foreground disabled:opacity-60 aria-invalid:border-destructive [&>span:first-child]:truncate', className)}>
      <SelectPrimitive.Value />
      <SelectPrimitive.Icon asChild><ChevronDown className="size-3.5 shrink-0 text-muted-foreground transition-transform group-data-[state=open]:rotate-180" /></SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
    <SelectPrimitive.Portal>
      <SelectPrimitive.Content position="popper" sideOffset={6} collisionPadding={12} className="z-[100] max-h-[min(320px,var(--radix-select-content-available-height))] min-w-[var(--radix-select-trigger-width)] max-w-[calc(100vw-24px)] overflow-hidden rounded-xl border bg-white text-foreground shadow-[0_8px_30px_-8px_rgb(0_0_0/0.2)]">
        <SelectPrimitive.ScrollUpButton className="flex h-6 items-center justify-center bg-white text-muted-foreground"><ChevronUp className="size-4" /></SelectPrimitive.ScrollUpButton>
        <SelectPrimitive.Viewport className="p-1.5">{children}</SelectPrimitive.Viewport>
        <SelectPrimitive.ScrollDownButton className="flex h-6 items-center justify-center bg-white text-muted-foreground"><ChevronDown className="size-4" /></SelectPrimitive.ScrollDownButton>
      </SelectPrimitive.Content>
    </SelectPrimitive.Portal>
  </SelectPrimitive.Root>
}
export function SelectItem({ value, disabled, children }: { value: string | number; disabled?: boolean; children: ReactNode }) {
  return <SelectPrimitive.Item value={encode(value)} disabled={disabled} className="relative flex min-h-9 cursor-default select-none items-center rounded-md py-2 pl-3 pr-9 text-[13px] outline-none data-[highlighted]:bg-muted data-[state=checked]:bg-primary/5 data-[state=checked]:font-medium data-[state=checked]:text-primary data-[disabled]:pointer-events-none data-[disabled]:opacity-40">
    <SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
    <SelectPrimitive.ItemIndicator className="absolute right-3 flex items-center"><Check className="size-3.5" /></SelectPrimitive.ItemIndicator>
  </SelectPrimitive.Item>
}
