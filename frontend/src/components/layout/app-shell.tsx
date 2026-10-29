import { versionLabel } from '@/lib/app-version'
import { useEffect, type ReactNode } from 'react'
import { useUIStore } from '@/stores/ui'
import { Drawer } from '@/components/shared/drawer'
import type { CurrentUser } from '@/permissions'
import { Header } from './header'
import { Sidebar } from './sidebar'
export function AppShell({ user, children, onLogout, signingOut }: { user: CurrentUser; children: ReactNode; onLogout: () => void; signingOut: boolean }) {
  const { sidebarOpen, setSidebarOpen } = useUIStore()
  useEffect(() => {
    const wide = matchMedia('(min-width: 1024px)')
    const close = () => { if (wide.matches) setSidebarOpen(false) }
    wide.addEventListener('change', close)
    return () => wide.removeEventListener('change', close)
  }, [setSidebarOpen])
  return <div className="min-h-dvh bg-background"><a href="#main-content" className="sr-only z-50 rounded bg-white p-3 focus:not-sr-only focus:fixed focus:left-4 focus:top-3">Skip to content</a><aside className="fixed inset-y-0 left-0 hidden h-dvh w-[14rem] min-h-0 overflow-hidden border-r border-border bg-surface lg:flex"><Sidebar user={user} /></aside><Drawer title="Navigation" open={sidebarOpen} onOpenChange={setSidebarOpen} side="left" bodyClassName="flex min-h-0 flex-1 overflow-hidden p-0"><Sidebar user={user} onNavigate={() => setSidebarOpen(false)} /></Drawer><div className="min-w-0 lg:pl-[14rem]"><Header user={user} onMenu={() => setSidebarOpen(true)} onLogout={onLogout} signingOut={signingOut} /><main id="main-content" tabIndex={-1} className="mx-auto max-w-[1440px] px-4 py-5 outline-none sm:px-6 sm:py-6"><div className="min-w-0">{children}</div></main><footer className="px-6 pb-4 text-xs text-muted-foreground">PWINT THIT <span className="mx-2 text-stone-300">·</span> Distribution management · {versionLabel}</footer></div></div>
}
