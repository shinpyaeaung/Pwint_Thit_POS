import * as Dialog from '@radix-ui/react-dialog'
import { motion, useReducedMotion } from 'framer-motion'
import { useRef, type ReactNode } from 'react'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
export type OverlayProps = { open: boolean; onOpenChange: (open: boolean) => void; title: string; description?: string; children: ReactNode; footer?: ReactNode; busy?: boolean; animated?: boolean; bodyClassName?: string; size?: 'default' | 'wide' }
export function Overlay({ open, onOpenChange, title, description, children, footer, busy, animated = true, drawer = false, side = 'right', bodyClassName, size = 'default' }: OverlayProps & { drawer?: boolean; side?: 'left' | 'right' }) {
  const reduced = useReducedMotion()
  const opener = useRef<HTMLElement | null>(null)
  return <Dialog.Root open={open} onOpenChange={value => { if (!busy) onOpenChange(value) }}><Dialog.Portal>
    <Dialog.Overlay className={cn('fixed inset-0 z-50 grid bg-black/40 backdrop-blur-[2px]', drawer ? (side === 'right' ? 'justify-items-end' : 'justify-items-start') : 'place-items-center p-4')}>
      <Dialog.Content asChild onOpenAutoFocus={() => { opener.current = document.activeElement as HTMLElement }} onCloseAutoFocus={event => { event.preventDefault(); opener.current?.focus() }} onEscapeKeyDown={event => { if (busy) event.preventDefault() }} onInteractOutside={event => { if (busy) event.preventDefault() }}>
        <motion.div initial={reduced || !animated ? false : { opacity: 0, ...(drawer ? { x: side === 'right' ? 16 : -16 } : { y: 8, scale: 0.98 }) }} animate={{ opacity: 1, x: 0, y: 0, scale: 1 }} transition={{ duration: animated ? 0.2 : 0, ease: [0.16, 1, 0.3, 1] }} aria-busy={busy || undefined} className={cn('relative flex min-h-0 min-w-0 flex-col overflow-hidden border border-border bg-surface text-foreground outline-none', drawer ? 'h-dvh w-full max-w-[30rem]' : 'max-h-[calc(100dvh_-_2rem)] w-full rounded-xl', !drawer && (size === 'wide' ? 'max-w-5xl' : 'max-w-lg'))} style={{boxShadow: 'var(--shadow-overlay)'}}>
          <div className="flex shrink-0 items-start justify-between gap-4 border-b border-border p-5"><div className="min-w-0 break-words"><Dialog.Title className="text-lg font-bold tracking-tight">{title}</Dialog.Title>{description ? <Dialog.Description className="mt-2 text-sm leading-6 text-muted-foreground">{description}</Dialog.Description> : <Dialog.Description className="sr-only">{title}</Dialog.Description>}</div><Dialog.Close asChild><Button aria-label="Close" className="shrink-0" variant="ghost" size="icon-sm" disabled={busy}><X /></Button></Dialog.Close></div>
          <div className={cn("min-h-0 flex-auto overflow-y-auto overscroll-contain p-5", bodyClassName)}>{children}</div>
          {footer && <div className="flex shrink-0 flex-wrap justify-end gap-2 border-t border-border bg-muted p-4">{footer}</div>}
        </motion.div>
      </Dialog.Content>
    </Dialog.Overlay>
  </Dialog.Portal></Dialog.Root>
}
