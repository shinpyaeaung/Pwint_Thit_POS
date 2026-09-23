import { cva, type VariantProps } from 'class-variance-authority'
import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'
const styles = cva('inline-flex items-center gap-1.5 whitespace-nowrap rounded-md border px-2 py-1 text-[11px] font-medium', { variants: { tone: { neutral: 'border-border bg-muted text-muted-foreground', success: 'border-emerald-200 bg-emerald-50 text-emerald-800', warning: 'border-brand-yellow/35 bg-accent text-amber-900', danger: 'border-red-200 bg-red-50 text-red-800', info: 'border-blue-200 bg-blue-50 text-blue-800' } }, defaultVariants: { tone: 'neutral' } })
export function StatusBadge({ children, tone, className }: VariantProps<typeof styles> & { children: ReactNode; className?: string }) {
  return <span className={cn(styles({ tone }), className)}><span aria-hidden="true" className="size-1.5 rounded-full bg-current" />{children}</span>
}
