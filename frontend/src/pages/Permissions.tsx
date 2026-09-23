import { useQuery } from '@tanstack/react-query'
import { requestJSON } from '@/services/api'
export type Permission = { code: string; description: string; sensitive: boolean }
export default function Permissions() {
  const query = useQuery({ queryKey: ['permission-catalog'], queryFn: ({ signal }) => requestJSON<{ permissions: Permission[] }>('/permissions', { signal }), retry: false })
  return <section className="mx-auto max-w-5xl px-6 py-10"><h1 className="text-2xl font-semibold">Permission catalog</h1><p className="mt-2 text-sm text-muted-foreground">Access is checked by the server for every protected request.</p>
    {query.isPending && <p role="status" className="mt-6">Loading permissions…</p>}{query.error && <p role="alert" className="mt-6 text-red-700">{query.error.message}</p>}
    <div className="mt-6 grid gap-3 sm:grid-cols-2">{query.data?.permissions.map(p => <div key={p.code} className="rounded-xl border bg-white p-4"><p className="font-mono text-sm">{p.code}</p><p className="mt-1 text-xs text-muted-foreground">{p.description}</p>{p.sensitive && <span className="mt-2 inline-block rounded bg-amber-50 px-2 py-1 text-xs text-amber-900">Sensitive access</span>}</div>)}</div>
  </section>
}
