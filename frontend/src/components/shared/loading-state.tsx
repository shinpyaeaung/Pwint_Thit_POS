export function LoadingState({ label = 'Loading records…' }: { label?: string }) {
  return <div role="status" aria-live="polite" className="space-y-3 p-6"><p className="text-sm text-muted-foreground">{label}</p><div aria-hidden="true" className="space-y-2 motion-safe:animate-pulse">{[1, 2, 3].map(n => <div key={n} className="h-8 rounded-lg bg-muted" />)}</div></div>
}
