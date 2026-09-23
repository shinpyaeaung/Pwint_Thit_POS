import { PackageOpen } from 'lucide-react'
import type { ReactNode } from 'react'
export function EmptyState({ title = 'No records yet', description, action }: { title?: string; description?: string; action?: ReactNode }) {
  return <div className="flex flex-col items-center px-6 py-12 text-center"><span className="mb-4 rounded-xl border bg-muted p-3"><PackageOpen aria-hidden="true" className="size-5 text-muted-foreground" /></span><h2 className="text-sm font-semibold">{title}</h2>{description && <p className="mt-2 max-w-sm text-sm leading-6 text-muted-foreground">{description}</p>}{action && <div className="mt-5">{action}</div>}</div>
}
