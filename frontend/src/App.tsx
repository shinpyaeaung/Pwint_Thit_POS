import { useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Sprout } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useSession } from '@/hooks/use-session'
import { can, permissions, protectedPages } from '@/permissions'
import { requestJSON } from '@/services/api'
import Login from '@/pages/Login'
import Workspace from '@/pages/Workspace'
import Users from '@/pages/Users'
import Permissions from '@/pages/Permissions'

export default function App() {
  const session = useSession()
  const client = useQueryClient()
  const path = window.location.pathname
  const logout = useMutation({ mutationFn: () => requestJSON('/auth/logout', { method: 'POST' }), onSuccess: async () => { await client.cancelQueries(); client.clear(); window.location.replace('/login') } })
  useEffect(() => {
    if (session.isSuccess && !session.data && path !== '/login') { client.removeQueries({ predicate: q => q.queryKey[0] !== 'session' }); window.location.replace(`/login?next=${encodeURIComponent(path)}`) }
    if (session.data && path === '/login') window.location.replace('/')
  }, [session.data, session.isSuccess, path, client])
  if (session.isPending) return <main className="grid min-h-screen place-items-center"><p role="status">Opening your workspace…</p></main>
  if (session.isError) return <main className="mx-auto max-w-md p-10"><h1 className="text-xl font-semibold">Unable to check your session</h1><p role="alert" className="my-4 text-sm text-muted-foreground">{session.error.message}</p><Button onClick={() => void session.refetch()}>Try again</Button></main>
  if (!session.data) return path === '/login' ? <Login /> : <p role="status" className="p-8">Redirecting to sign in…</p>
  const user = session.data
  const required = protectedPages[path]
  const known = Object.hasOwn(protectedPages, path)
  return <div className="min-h-screen bg-background"><header className="border-b bg-white"><div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-5 py-4"><a href="/" className="flex items-center gap-2 font-bold text-primary"><Sprout />PWINT THIT</a><nav aria-label="Main navigation" className="flex gap-4 text-sm"><a href="/">Workspace</a>{can(user, permissions.usersManage) && <a href="/users">Users & access</a>}{can(user, permissions.permissionsManage) && <a href="/permissions">Permissions</a>}</nav><div className="flex items-center gap-3"><div className="text-right"><p className="text-sm font-medium">{user.display_name}</p><p className="text-xs text-muted-foreground">{user.role === 'SUPER_ADMIN' ? 'Super Admin' : 'Staff Admin'}</p></div><Button variant="outline" size="sm" onClick={() => logout.mutate()} disabled={logout.isPending}>{logout.isPending ? 'Signing out…' : 'Sign out'}</Button></div></div></header>
    {logout.error && <p role="alert" className="mx-auto max-w-5xl p-4 text-red-700">{logout.error.message}</p>}
    {!known ? <main className="p-10"><h1>Page not found</h1><a href="/">Return to workspace</a></main> : required && !can(user, required) ? <main className="mx-auto max-w-xl p-10"><h1 className="text-2xl font-semibold">Access restricted</h1><p className="mt-3 text-muted-foreground">Your account does not have permission to view this page. Contact your Super Admin.</p><a href="/" className="mt-5 inline-block text-primary">Return to workspace</a></main> : path === '/users' ? <Users current={user} /> : path === '/permissions' ? <Permissions /> : <Workspace />}
  </div>
}
