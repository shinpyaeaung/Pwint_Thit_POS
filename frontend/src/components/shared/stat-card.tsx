import type { ReactNode } from 'react'
export function StatCard({ label, value, detail, icon }: { label: string; value: ReactNode; detail?: ReactNode; icon?: ReactNode }) {
  return <section aria-label={label} className="rounded-xl border bg-white p-5"><div className="flex items-center justify-between gap-2"><h2 className="text-xs font-medium text-muted-foreground">{label}</h2>{icon && <span aria-hidden="true" className="text-muted-foreground [&>svg]:size-4">{icon}</span>}</div><div className="mt-3 break-words text-2xl font-semibold tracking-tight tabular-nums">{value}</div>{detail && <div className="mt-2 text-xs leading-5 text-muted-foreground">{detail}</div>}</section>
}
