import * as Dialog from '@radix-ui/react-dialog'
import { motion, useReducedMotion } from 'framer-motion'
import { useRef, type ReactNode } from 'react'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
export type OverlayProps = { open: boolean; onOpenChange: (open: boolean) => void; title: string; description?: string; children: ReactNode; footer?: ReactNode; busy?: boolean; fullScreen?: boolean }
export function Overlay({ open, onOpenChange, title, description, children, footer, busy, fullScreen = false, drawer = false, side = 'right' }: OverlayProps & { drawer?: boolean; side?: 'left' | 'right' }) {
  const reduced = useReducedMotion()
  const opener = useRef<HTMLElement | null>(null)
  return <Dialog.Root open={open} onOpenChange={value => { if (!busy) onOpenChange(value) }}><Dialog.Portal><Dialog.Overlay className="fixed inset-0 z-40 bg-black/35" /><Dialog.Content asChild onOpenAutoFocus={() => { opener.current = document.activeElement as HTMLElement }} onCloseAutoFocus={event => { event.preventDefault(); opener.current?.focus() }} onEscapeKeyDown={event => { if (busy) event.preventDefault() }} onInteractOutside={event => { if (busy) event.preventDefault() }}>
    <motion.div initial={reduced ? false : { opacity: 0, ...(drawer ? { x: side === 'right' ? 12 : -12 } : { y: 6 }) }} animate={{ opacity: 1, x: 0, y: 0 }} transition={{ duration: 0.15 }} aria-busy={busy || undefined} className={cn('fixed z-50 flex flex-col overflow-hidden border bg-white text-foreground shadow-xl outline-none', drawer ? `inset-y-0 ${side === 'right' ? 'right-0' : 'left-0'} h-dvh w-[min(100%,30rem)]` : fullScreen ? 'inset-4 h-[calc(100dvh_-_2rem)] rounded-2xl' : 'inset-0 m-auto h-fit max-h-[calc(100dvh_-_2rem)] w-[calc(100%_-_2rem)] max-w-lg rounded-2xl')}>
      <div className="flex shrink-0 items-start justify-between gap-4 border-b p-5"><div><Dialog.Title className="text-lg font-semibold tracking-tight">{title}</Dialog.Title>{description ? <Dialog.Description className="mt-2 text-sm leading-6 text-muted-foreground">{description}</Dialog.Description> : <Dialog.Description className="sr-only">{title}</Dialog.Description>}</div><Dialog.Close asChild><Button aria-label="Close" variant="ghost" size="icon-sm" disabled={busy}><X /></Button></Dialog.Close></div><div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-5">{children}</div>{footer && <div className="flex shrink-0 flex-wrap justify-end gap-2 border-t bg-muted/40 p-4">{footer}</div>}
    </motion.div>
  </Dialog.Content></Dialog.Portal></Dialog.Root>
}
