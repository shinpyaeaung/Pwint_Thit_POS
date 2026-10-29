import { cva, type VariantProps } from 'class-variance-authority'
import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'
const styles = cva('inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border px-2.5 py-1 text-xs font-medium', { variants: { tone: { neutral: 'border-border bg-background text-muted-foreground', success: 'border-emerald-200 bg-emerald-50 text-emerald-700', warning: 'border-amber-200 bg-amber-50 text-amber-800', danger: 'border-red-200 bg-red-50 text-red-700', info: 'border-blue-200 bg-blue-50 text-blue-700' } }, defaultVariants: { tone: 'neutral' } })
export function StatusBadge({ children, tone, className }: VariantProps<typeof styles> & { children: ReactNode; className?: string }) {
  return <span className={cn(styles({ tone }), className)}><span aria-hidden="true" className="size-1.5 rounded-full bg-current" />{children}</span>
}
