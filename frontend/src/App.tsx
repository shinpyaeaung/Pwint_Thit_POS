import { lazy, Suspense, useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { AppShell } from '@/components/layout/app-shell'
import { EmptyState, LoadingState, PermissionGuard } from '@/components/shared'
const DesignSystem = lazy(() => import('@/pages/DesignSystem'))
import { Button } from '@/components/ui/button'
import { useSession } from '@/hooks/use-session'
const Products = lazy(() => import('@/pages/products/Products'))
const CatalogPage = lazy(() => import('@/pages/products/Catalog'))
import { pagePermission } from '@/permissions'
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
  if (session.isPending) return <div className="mx-auto mt-20 max-w-md"><LoadingState label="Opening your workspace…" /></div>
  if (session.isError) return <main className="mx-auto max-w-md p-10"><h1 className="text-xl font-semibold">Unable to check your session</h1><p role="alert" className="my-4 text-sm text-muted-foreground">{session.error.message}</p><Button onClick={() => void session.refetch()}>Try again</Button></main>
  if (!session.data) return path === '/login' ? <Login /> : <p role="status" className="p-8">Redirecting to sign in…</p>
  const user = session.data
  const required = pagePermission(path)
  const known = required !== undefined
  const restricted = <EmptyState title="Access restricted" description="Your account does not have permission to view this page. Contact your Super Admin." action={<Button asChild variant="outline"><a href="/">Return to workspace</a></Button>} />
  const page = path === '/products' || path.startsWith('/products/') ? <Products current={user} /> : path === '/catalog' ? <CatalogPage /> : path === '/users' ? <Users current={user} /> : path === '/permissions' ? <Permissions /> : path === '/design-system' ? <DesignSystem current={user} /> : <Workspace />
  return <AppShell user={user} onLogout={() => logout.mutate()} signingOut={logout.isPending}>
    {logout.error && <p role="alert" className="mb-4 text-sm text-destructive">{logout.error.message}</p>}
    <Suspense fallback={<LoadingState label="Opening page…" />}>{!known ? <EmptyState title="Page not found" action={<a href="/">Return to workspace</a>} /> : required ? <PermissionGuard user={user} permission={required} fallback={restricted}>{page}</PermissionGuard> : page}</Suspense>
  </AppShell>
}
