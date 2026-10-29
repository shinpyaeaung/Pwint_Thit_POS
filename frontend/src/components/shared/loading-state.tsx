export function LoadingState({ label = 'Loading records…' }: { label?: string }) {
  return <div role="status" aria-live="polite" className="space-y-3 p-6"><p className="text-sm font-medium text-muted-foreground">{label}</p><div aria-hidden="true" className="space-y-2.5">{[1, 2, 3].map(n => <div key={n} className="skeleton h-8" style={{ animationDelay: `${n * 0.1}s` }} />)}</div></div>
}
