import type { ReactNode } from 'react'
export function PageHeader({ eyebrow, title, description, actions }: { eyebrow?: string; title: string; description?: string; actions?: ReactNode }) {
  return <div className="mb-5 flex flex-wrap items-start justify-between gap-4"><div className="min-w-0"><div className="flex items-center gap-3">{eyebrow && <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{eyebrow}</p>}</div><h1 className="text-2xl font-semibold tracking-tight text-foreground">{title}</h1>{description && <p className="mt-1.5 max-w-3xl text-[13px] leading-5 text-muted-foreground">{description}</p>}</div>{actions && <div className="flex flex-wrap gap-2">{actions}</div>}</div>
}
