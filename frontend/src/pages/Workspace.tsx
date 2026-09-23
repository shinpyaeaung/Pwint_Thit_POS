import { motion } from 'framer-motion'
import { ArrowRight, Check, ChevronDown, CircleAlert, Database, Layers3, RefreshCw, Server } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useHealth } from '@/hooks/use-health'
import { useUIStore } from '@/stores/ui'

export default function Workspace() {
  const health = useHealth()
  const { detailsOpen, toggleDetails } = useUIStore()
  const connected = health.isSuccess && !health.isError
  return (
    <div className="min-h-screen bg-background text-foreground">
      <main className="mx-auto max-w-6xl px-5 py-10 sm:px-8 sm:py-16">
        <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.2 }}>
          <div className="mb-5 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.15em] text-primary"><span className="h-px w-7 bg-primary" /> Phase 01 · Project foundation</div>
          <h1 className="max-w-2xl text-3xl font-semibold tracking-tight sm:text-5xl sm:leading-tight">A solid start for<br /><span className="text-muted-foreground">every business journey.</span></h1>
          <p className="mt-5 max-w-xl text-sm leading-7 text-muted-foreground sm:text-base">The foundation for Pwint Thit's distribution system. Check the connection below before building the first business module.</p>

          <section className="mt-10 overflow-hidden rounded-2xl border bg-white shadow-sm" aria-labelledby="connection-title">
            <div className="flex flex-wrap items-center justify-between gap-4 border-b px-6 py-5">
              <div><h2 id="connection-title" className="font-semibold">Workspace connection</h2><p className="mt-1 text-xs text-muted-foreground">Live status · checked every 30 seconds</p></div>
              <Button variant="outline" size="sm" onClick={() => void health.refetch()} disabled={health.isFetching}><RefreshCw className="size-4" />{health.isFetching ? 'Checking…' : 'Check again'}</Button>
            </div>
            <div className="grid gap-6 p-6 sm:grid-cols-3 sm:gap-8">
              {[
                { icon: Layers3, title: 'Workspace', text: 'Frontend is running', ok: true },
                { icon: Server, title: 'API connection', text: connected ? 'Backend is responding' : health.isPending ? 'Connecting…' : 'Connection needs attention', ok: connected },
                { icon: Database, title: 'Database', text: connected ? 'PostgreSQL is connected' : health.isPending ? 'Waiting for server…' : 'Connection not verified', ok: connected },
              ].map(item => <div key={item.title} className="flex items-start gap-3"><span className="rounded-xl bg-muted p-3"><item.icon className="size-5 text-muted-foreground" /></span><div><h3 className="text-sm font-semibold">{item.title}</h3><p className="mt-2 flex items-center gap-1.5 text-xs text-muted-foreground">{item.ok && <Check className="size-3.5 text-emerald-700" />}{item.text}</p></div></div>)}
            </div>
            <div role="status" aria-live="polite" className={`flex items-center gap-2 border-t px-6 py-4 text-sm ${health.isError ? 'bg-amber-50 text-amber-900' : connected ? 'bg-emerald-50/60 text-emerald-800' : 'bg-muted text-muted-foreground'}`}>
              {health.isError ? <CircleAlert className="size-4 shrink-0" /> : connected ? <Check className="size-4 shrink-0" /> : <RefreshCw className="size-4 shrink-0" />}
              {health.isError ? health.error.message : connected ? 'All systems connected. The foundation is ready.' : 'Checking the workspace connection…'}
            </div>
          </section>

          <div className="mt-8 grid gap-8 sm:grid-cols-[1.6fr_1fr]">
            <section className="rounded-2xl border border-dashed p-6" aria-labelledby="next-title"><span className="text-xs font-medium text-muted-foreground">BUILT ONE MODULE AT A TIME</span><h2 id="next-title" className="mt-3 text-lg font-semibold">Ready for the next phase</h2><p className="mt-2 text-sm leading-6 text-muted-foreground">Business modules will be added step by step, with each workflow connected and tested from database to screen.</p><div className="mt-5 flex flex-wrap items-center gap-2 text-xs font-medium"><span>Database</span><ArrowRight className="size-3 text-primary" /><span>API & tests</span><ArrowRight className="size-3 text-primary" /><span>UI & integration</span></div></section>
            <section className="py-2"><Button variant="ghost" onClick={toggleDetails} aria-expanded={detailsOpen} aria-controls="foundation-details" className="w-full justify-between">Foundation details<ChevronDown className={`size-4 transition-transform ${detailsOpen ? 'rotate-180' : ''}`} /></Button>{detailsOpen && <div id="foundation-details" className="px-4 pt-3 text-sm leading-7 text-muted-foreground"><p>React · TypeScript · Go · PostgreSQL</p><p>MMK base currency</p><p>Business features are planned for later phases.</p></div>}<p className="mt-5 px-4 text-xs leading-6 text-muted-foreground">From purchase to real cost.<br />From inventory to informed decisions.</p></section>
          </div>
        </motion.div>
      </main>
      <footer className="mx-auto max-w-6xl px-5 pb-7 text-xs text-muted-foreground sm:px-8">Pwint Thit Distribution <span className="mx-2 text-border">/</span> Foundation workspace</footer>
    </div>
  )
}
