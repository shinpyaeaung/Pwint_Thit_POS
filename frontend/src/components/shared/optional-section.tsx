import { useState, type ReactNode } from 'react'

// Collapsing hides fields without silently discarding entered or recorded values.
export function OptionalSection({ title, children, defaultOpen = false }: { title: string; children: ReactNode; defaultOpen?: boolean }) {
 const [expanded, setExpanded] = useState<boolean|null>(null)
 const open=expanded??defaultOpen
 return <section className="min-w-0 rounded-xl border p-4"><label className="flex cursor-pointer items-center gap-3 text-sm font-medium"><input aria-label={title} type="checkbox" className="accent-primary" checked={open} onChange={e => setExpanded(e.target.checked)} />{title}<span aria-hidden="true" className="ml-auto text-xs font-normal text-muted-foreground">{open ? 'Enabled' : 'Optional'}</span></label>{open && <div className="mt-4 min-w-0 space-y-4">{children}</div>}</section>
}
