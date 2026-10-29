import { versionLabel } from '@/lib/app-version'
import { useState, type FormEvent } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { ArrowRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { pagePermission } from '@/permissions'
import { requestJSON } from '@/services/api'

export default function Login() {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const client = useQueryClient()
  const login = useMutation({ mutationFn: () => requestJSON('/auth/login', { method: 'POST', body: JSON.stringify({ username, password }) }),
    onSuccess: async () => { setPassword(''); await client.cancelQueries(); client.clear();
      const next = new URLSearchParams(window.location.search).get('next')
      window.location.replace(next && pagePermission(next) !== undefined ? next : '/')
    }, onError: () => setPassword(''),
  })
  const submit = (event: FormEvent) => { event.preventDefault(); if (!login.isPending) login.mutate() }
  return <div className="grid min-h-dvh bg-surface lg:grid-cols-[1fr_1fr]">
    <aside className="hidden flex-col justify-between border-r bg-background p-12 lg:flex xl:p-16">
      <div className="flex items-center gap-3"><span aria-hidden="true" className="flex size-10 items-center justify-center border-b-4 border-brand-yellow bg-primary font-semibold text-white">PT</span><div><p className="text-sm font-semibold tracking-wide">PWINT THIT</p><p className="text-xs text-muted-foreground">Distribution management</p></div></div>
      <div className="py-16"><p className="mb-5 text-xs font-semibold uppercase tracking-wide text-primary">Operations workspace</p><h1 className="max-w-md text-4xl font-semibold leading-tight tracking-tight">From supplier<br />to your customer.</h1><p className="mt-5 max-w-sm text-sm leading-6 text-muted-foreground">Purchasing, stock and sales in one connected workspace.</p><ol className="mt-10 max-w-sm divide-y border-y text-sm">{['Purchase & receive', 'Track stock & costs', 'Sell & reconcile'].map((label,i)=><li key={label} className="flex gap-5 py-4"><span className="text-xs tabular-nums text-muted-foreground">0{i+1}</span>{label}</li>)}</ol></div>
      <p className="text-xs text-muted-foreground">Pwint Thit Distribution · {versionLabel}</p>
    </aside>
    <main className="flex items-center justify-center px-6 py-12 sm:px-12">
      <div className="w-full max-w-sm">
        <div className="mb-10 flex items-center gap-3 lg:hidden"><span aria-hidden="true" className="flex size-9 items-center justify-center border-b-4 border-brand-yellow bg-primary font-semibold text-white">PT</span><span className="text-sm font-semibold tracking-wide">PWINT THIT</span></div>
        <p className="mb-3 text-xs font-medium text-muted-foreground">Your account</p><h2 className="text-2xl font-semibold tracking-tight">Sign in to your workspace</h2><p className="mt-2 text-sm leading-6 text-muted-foreground">Enter your username and password to continue.</p>
        <form onSubmit={submit} className="mt-7 space-y-5">
          <label className="block text-xs font-semibold">Username<input className="field mt-2" autoComplete="username" name="username" required maxLength={100} value={username} onChange={e=>setUsername(e.target.value)} autoFocus /></label>
          <label className="block text-xs font-semibold">Password<input className="field mt-2" type="password" autoComplete="current-password" name="password" required maxLength={128} value={password} onChange={e=>setPassword(e.target.value)} /></label>
          {login.error&&<p role="alert" className="border-l-2 border-destructive bg-red-50 p-3 text-sm text-red-800">{login.error.message}</p>}
          <Button type="submit" disabled={login.isPending} className="h-10 w-full">{login.isPending?'Signing in…':'Sign in'}<ArrowRight size={16}/></Button>
        </form>
        <p className="mt-8 border-t pt-5 text-xs leading-5 text-muted-foreground">Need access or help with your password?<br/>Contact your Super Admin. · {versionLabel}</p>
      </div>
    </main>
  </div>
}
