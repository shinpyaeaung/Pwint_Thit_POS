import type { ReactNode } from 'react'
export function PageHeader({ eyebrow, title, description, actions }: { eyebrow?: string; title: string; description?: string; actions?: ReactNode }) {
  return <div className="mb-6 flex flex-wrap items-end justify-between gap-4"><div>{eyebrow && <p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">{eyebrow}</p>}<h1 className="text-2xl font-semibold tracking-tight">{title}</h1>{description && <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">{description}</p>}</div>{actions && <div className="flex flex-wrap gap-2">{actions}</div>}</div>
}
