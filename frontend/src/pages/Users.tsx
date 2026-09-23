import { useState, type FormEvent } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { UserPlus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PageHeader, DataTable, SearchInput, FilterBar, Modal, Drawer, ConfirmDialog, FormField, LoadingState, StatusBadge, EmptyState } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { canAssignPermissions, type CurrentUser } from '@/permissions'
import type { Permission } from './Permissions'
type User = Omit<CurrentUser, 'permissions'> & { active: boolean }
export default function Users({ current }: { current: CurrentUser }) {
  const client = useQueryClient()
  const [selected, setSelected] = useState<User | null>(null)
  const [creating, setCreating] = useState(false)
  const [created, setCreated] = useState(false)
  const [search, setSearch] = useState('')
  const [role, setRole] = useState('all')
  const users = useQuery({ queryKey: ['users'], queryFn: ({ signal }) => requestJSON<{ users: User[] }>('/users', { signal }), retry: false })
  const create = useMutation({ mutationFn: (body: object) => requestJSON('/users', { method: 'POST', body: JSON.stringify(body) }), onSuccess: () => { setCreated(true); setCreating(false); void client.invalidateQueries({ queryKey: ['users'] }) } })
  function submit(event: FormEvent<HTMLFormElement>) { event.preventDefault(); if (create.isPending) return; create.mutate(Object.fromEntries(new FormData(event.currentTarget))) }
  const rows = (users.data?.users || []).filter(u => (role === 'all' || u.role === role) && `${u.display_name} ${u.username}`.toLowerCase().includes(search.toLowerCase()))
  return <><PageHeader eyebrow="System / People" title="Users & access" description="Manage staff accounts and their access to daily operations." actions={<Button onClick={() => { create.reset(); setCreated(false); setCreating(true) }}><UserPlus />New staff account</Button>} />
    {created && <p role="status" className="mb-4 rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">Staff account created.</p>}
    <FilterBar onReset={search || role !== 'all' ? () => { setSearch(''); setRole('all') } : undefined} summary={`${rows.length} accounts`}><SearchInput value={search} onValueChange={setSearch} label="Search users" placeholder="Search by name or username…" /><label className="flex items-center gap-2 text-xs text-muted-foreground">Role<select className="field w-auto" value={role} onChange={e => setRole(e.target.value)}><option value="all">All roles</option><option value="SUPER_ADMIN">Super Admin</option><option value="STAFF_ADMIN">Staff Admin</option></select></label></FilterBar>
    <DataTable key={`${search}:${role}`} caption="User accounts" rows={rows} rowKey={u => u.id} loading={users.isPending} error={users.error?.message} onRetry={() => void users.refetch()} columns={[
      { id: 'name', header: 'Account', compare: (a, b) => a.display_name.localeCompare(b.display_name), cell: u => <div className="min-w-36"><p className="font-medium">{u.display_name}</p><p className="mt-1 text-xs text-muted-foreground">{u.username}</p></div> },
      { id: 'role', header: 'Role', cell: u => <span className="whitespace-nowrap text-xs">{u.role === 'SUPER_ADMIN' ? 'Super Admin · Full access' : 'Staff Admin'}</span> },
      { id: 'status', header: 'Status', cell: u => <StatusBadge tone={u.active ? 'success' : 'neutral'}>{u.active ? 'Active' : 'Inactive'}</StatusBadge> },
      { id: 'actions', header: 'Access', align: 'right', cell: u => canAssignPermissions(current) && u.role === 'STAFF_ADMIN' ? <Button variant="outline" size="sm" aria-label={`Manage permissions for ${u.username}`} onClick={() => setSelected(u)}>Manage permissions</Button> : <span className="text-xs text-muted-foreground">{u.role === 'SUPER_ADMIN' ? 'Full access' : 'Owner managed'}</span> },
    ]} empty={<EmptyState title="No matching accounts" description="Try another name or reset the role filter." />} />
    <p className="mt-4 text-xs leading-5 text-muted-foreground">Staff accounts start with no permissions. A Super Admin assigns access; the server checks every protected action.</p>
    <Modal open={creating} onOpenChange={setCreating} title="Create Staff Admin" description="Add an account for daily operations. Assign permissions after creating it." busy={create.isPending} footer={<><Button variant="outline" disabled={create.isPending} onClick={() => setCreating(false)}>Cancel</Button><Button type="submit" form="create-staff" disabled={create.isPending}>{create.isPending ? 'Creating…' : 'Create Staff Admin'}</Button></>}>
      <form id="create-staff" onSubmit={submit} className="space-y-4"><FormField label="Display name" required>{p => <input {...p} name="display_name" className="field" maxLength={200} />}</FormField><FormField label="Username" required hint="3–100 letters, numbers, dots, underscores or hyphens.">{p => <input {...p} name="username" className="field" minLength={3} maxLength={100} autoComplete="off" pattern="[a-zA-Z0-9][a-zA-Z0-9._\-]{2,99}" />}</FormField><FormField label="Initial password" required hint="At least 12 characters; no more than 128 UTF-8 bytes.">{p => <input {...p} name="password" className="field" type="password" autoComplete="new-password" minLength={12} maxLength={128} />}</FormField>{create.error && <p role="alert" className="text-sm text-destructive">{create.error.message}</p>}</form>
    </Modal>
    {selected && <PermissionEditor key={selected.id} user={selected} onClose={() => setSelected(null)} />}
  </>
}
function PermissionEditor({ user, onClose }: { user: User; onClose: () => void }) {
  const client = useQueryClient()
  const [confirm, setConfirm] = useState(false)
  const catalog = useQuery({ queryKey: ['permission-catalog'], queryFn: ({ signal }) => requestJSON<{ permissions: Permission[] }>('/permissions', { signal }), retry: false })
  const grants = useQuery({ queryKey: ['user-permissions', user.id], queryFn: ({ signal }) => requestJSON<{ permissions: string[] }>(`/users/${user.id}/permissions`, { signal }), retry: false })
  const [edited, setEdited] = useState<string[] | null>(null)
  const selected = edited ?? grants.data?.permissions ?? []
  const save = useMutation({ mutationFn: () => requestJSON(`/users/${user.id}/permissions`, { method: 'PUT', body: JSON.stringify({ permissions: selected }) }), onSuccess: async () => { await client.invalidateQueries({ queryKey: ['user-permissions', user.id] }); onClose() } })
  return <><Drawer open onOpenChange={open => { if (!open) onClose() }} title={`Permissions for ${user.username}`} description="Changes apply to this staff account immediately after saving." busy={save.isPending} footer={<><span className="mr-auto self-center text-xs text-muted-foreground">{selected.length} selected</span><Button disabled={!catalog.isSuccess || !grants.isSuccess || save.isPending} onClick={() => setConfirm(true)}>Save permissions</Button></>}>
    {(catalog.isPending || grants.isPending) && <LoadingState label="Loading permissions…" />}{(catalog.error || grants.error) && <p role="alert" className="text-sm text-destructive">Could not load permissions. Close and try again.</p>}
    {catalog.isSuccess && grants.isSuccess && <div className="space-y-2">{catalog.data.permissions.map(p => <label key={p.code} className="flex items-start gap-3 rounded-lg border p-3 text-sm"><input type="checkbox" checked={selected.includes(p.code)} onChange={e => setEdited(e.target.checked ? [...selected, p.code] : selected.filter(v => v !== p.code))} className="mt-1 accent-primary" /><span><span className="block font-mono text-xs">{p.code}</span><span className="mt-1 block text-xs leading-5 text-muted-foreground">{p.description}</span>{p.sensitive && <span className="mt-1 block text-[10px] font-medium text-amber-900">Sensitive access</span>}</span></label>)}</div>}
  </Drawer><ConfirmDialog open={confirm} onOpenChange={setConfirm} title="Update staff access?" description={`${user.username} will have ${selected.length} assigned permissions. This replaces their current access.`} confirmLabel="Apply permissions" onConfirm={() => save.mutate()} busy={save.isPending} error={save.error?.message} /></>
}
