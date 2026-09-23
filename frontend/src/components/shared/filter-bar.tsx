import type { ReactNode } from 'react'
import { Button } from '@/components/ui/button'
export function FilterBar({ children, onReset, summary }: { children: ReactNode; onReset?: () => void; summary?: string }) {
  return <div className="mb-4 flex flex-wrap items-center gap-3"><div className="flex min-w-0 flex-1 flex-wrap items-center gap-3">{children}</div>{summary && <span className="text-xs text-muted-foreground">{summary}</span>}{onReset && <Button type="button" variant="ghost" size="sm" onClick={onReset}>Reset filters</Button>}</div>
}
