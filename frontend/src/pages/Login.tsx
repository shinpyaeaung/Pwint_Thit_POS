import { useState, type FormEvent } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { motion } from 'framer-motion'
import { ArrowRight, LockKeyhole, Sprout } from 'lucide-react'
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
  return <div className="grid min-h-screen bg-background lg:grid-cols-2">
    <aside className="hidden flex-col justify-between bg-primary p-16 text-white lg:flex">
      <div className="flex items-center gap-3"><Sprout size={32} /><div><p className="font-bold tracking-wide">PWINT THIT</p><p className="text-xs tracking-[0.2em] text-white/70">DISTRIBUTION</p></div></div>
      <div><div className="mb-8 h-1 w-12 rounded bg-[#f7a712]" /><h1 className="max-w-lg text-5xl font-semibold leading-tight tracking-tight">Every product.<br />Every journey.<br />One clear picture.</h1><p className="mt-6 max-w-sm text-base leading-7 text-white/75">Your workspace for distribution, inventory, and informed business decisions.</p></div>
      <p className="text-xs text-white/65">Pwint Thit Distribution Management System</p>
    </aside>
    <main className="flex items-center justify-center px-6 py-14 sm:px-12">
      <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.2 }} className="w-full max-w-sm">
        <div className="mb-10 flex items-center gap-2 font-bold text-primary lg:hidden"><Sprout /> PWINT THIT</div>
        <div className="mb-6 inline-flex rounded-xl border bg-white p-3 text-primary"><LockKeyhole size={22} /></div>
        <h2 className="text-3xl font-semibold tracking-tight">Sign in to your workspace</h2><p className="mt-3 text-sm leading-6 text-muted-foreground">Welcome back. Enter your account details to continue.</p>
        <form onSubmit={submit} className="mt-8 space-y-5">
          <label className="block text-sm font-medium">Username<input className="field mt-2" autoComplete="username" name="username" required maxLength={100} value={username} onChange={e => setUsername(e.target.value)} autoFocus /></label>
          <label className="block text-sm font-medium">Password<input className="field mt-2" type="password" autoComplete="current-password" name="password" required maxLength={128} value={password} onChange={e => setPassword(e.target.value)} /></label>
          {login.error && <p role="alert" className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">{login.error.message}</p>}
          <Button type="submit" disabled={login.isPending} className="h-11 w-full">{login.isPending ? 'Signing in…' : 'Sign in'}<ArrowRight size={16} /></Button>
        </form>
        <p className="mt-8 text-xs leading-6 text-muted-foreground">Need access or help with your password?<br />Contact your Super Admin.</p>
      </motion.div>
    </main>
  </div>
}
