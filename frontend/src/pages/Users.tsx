import { useState, type FormEvent } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { requestJSON } from '@/services/api'
import { canAssignPermissions, type CurrentUser } from '@/permissions'
import type { Permission } from './Permissions'
type User = Omit<CurrentUser, 'permissions'> & { active: boolean }

export default function Users({ current }: { current: CurrentUser }) {
  const client = useQueryClient()
  const [selected, setSelected] = useState<User | null>(null)
  const [created, setCreated] = useState(false)
  const users = useQuery({ queryKey: ['users'], queryFn: ({ signal }) => requestJSON<{ users: User[] }>('/users', { signal }), retry: false })
  const create = useMutation({ mutationFn: (body: object) => requestJSON('/users', { method: 'POST', body: JSON.stringify(body) }), onSuccess: () => { setCreated(true); void client.invalidateQueries({ queryKey: ['users'] }) } })
  function submit(event: FormEvent<HTMLFormElement>) { event.preventDefault(); if (create.isPending) return; const form = event.currentTarget; const data = new FormData(form); setCreated(false); create.mutate(Object.fromEntries(data), { onSuccess: () => form.reset() }) }
  return <section className="mx-auto max-w-5xl px-6 py-10"><h1 className="text-2xl font-semibold">Users & access</h1><p className="mt-2 text-sm text-muted-foreground">Staff accounts begin with no permissions. A Super Admin assigns their access.</p>
    <form onSubmit={submit} className="mt-6 grid gap-4 rounded-2xl border bg-white p-5 sm:grid-cols-3">
      <label className="text-sm font-medium">Display name<input name="display_name" className="field mt-2" required maxLength={200} /></label>
      <label className="text-sm font-medium">Username<input name="username" className="field mt-2" required minLength={3} maxLength={100} autoComplete="off" pattern="[a-zA-Z0-9][a-zA-Z0-9._\-]{2,99}" /></label>
      <label className="text-sm font-medium">Initial password<input name="password" className="field mt-2" type="password" autoComplete="new-password" required minLength={12} maxLength={128} /></label>
      <div className="sm:col-span-3"><Button disabled={create.isPending} type="submit">{create.isPending ? 'Creating…' : 'Create Staff Admin'}</Button>{create.error && <p role="alert" className="mt-3 text-sm text-red-700">{create.error.message}</p>}{created && <p role="status" className="mt-3 text-sm text-emerald-800">Staff account created.</p>}</div>
    </form>
    {users.error && <p role="alert" className="mt-5 text-red-700">{users.error.message}</p>}
    <div className="mt-6 space-y-3">{users.data?.users.map(user => <div key={user.id} className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-white p-4"><div><p className="font-medium">{user.display_name}</p><p className="mt-1 text-xs text-muted-foreground">{user.username} · {user.role === 'SUPER_ADMIN' ? 'Super Admin · Full access' : 'Staff Admin'}{!user.active && ' · Inactive'}</p></div>{canAssignPermissions(current) && user.role === 'STAFF_ADMIN' && <Button variant="outline" size="sm" onClick={() => setSelected(user)}>Manage permissions for {user.username}</Button>}</div>)}</div>
    {selected && <PermissionEditor key={selected.id} user={selected} onClose={() => setSelected(null)} />}
  </section>
}
function PermissionEditor({ user, onClose }: { user: User; onClose: () => void }) {
  const client = useQueryClient()
  const catalog = useQuery({ queryKey: ['permission-catalog'], queryFn: ({ signal }) => requestJSON<{ permissions: Permission[] }>('/permissions', { signal }), retry: false })
  const grants = useQuery({ queryKey: ['user-permissions', user.id], queryFn: ({ signal }) => requestJSON<{ permissions: string[] }>(`/users/${user.id}/permissions`, { signal }), retry: false })
  const [edited, setEdited] = useState<string[] | null>(null)
  const selected = edited ?? grants.data?.permissions ?? []
  const save = useMutation({ mutationFn: () => requestJSON(`/users/${user.id}/permissions`, { method: 'PUT', body: JSON.stringify({ permissions: selected }) }), onSuccess: async () => { await client.invalidateQueries({ queryKey: ['user-permissions', user.id] }); onClose() } })
  return <section aria-label={`Permissions for ${user.username}`} className="mt-6 rounded-2xl border bg-white p-5"><div className="flex items-center justify-between gap-3"><h2 className="font-semibold">Permissions for {user.username}</h2><Button variant="ghost" onClick={onClose}>Close</Button></div>
    {(catalog.isPending || grants.isPending) && <p role="status" className="mt-4">Loading permissions…</p>}
    {(catalog.error || grants.error) && <p role="alert" className="mt-4 text-red-700">Could not load permissions. Close and try again.</p>}
    {catalog.isSuccess && grants.isSuccess && <><div className="my-5 grid max-h-96 gap-3 overflow-auto sm:grid-cols-2">{catalog.data.permissions.map(p => <label key={p.code} className="flex items-start gap-3 rounded-lg border p-3 text-sm"><input type="checkbox" checked={selected.includes(p.code)} onChange={e => setEdited(e.target.checked ? [...selected, p.code] : selected.filter(v => v !== p.code))} className="mt-1 accent-primary" /><span><span className="block font-mono text-xs">{p.code}</span><span className="text-xs text-muted-foreground">{p.description}{p.sensitive ? ' · Sensitive' : ''}</span></span></label>)}</div><Button onClick={() => save.mutate()} disabled={save.isPending}>{save.isPending ? 'Saving…' : 'Save permissions'}</Button>{save.error && <p role="alert" className="mt-3 text-red-700">{save.error.message}</p>}</>}
  </section>
}
