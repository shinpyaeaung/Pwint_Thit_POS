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
  return <div className="min-h-dvh bg-background"><a href="#main-content" className="sr-only z-50 rounded bg-white p-3 focus:not-sr-only focus:fixed focus:left-4 focus:top-3">Skip to content</a><aside className="fixed inset-y-0 left-0 hidden w-56 border-r bg-white lg:block"><Sidebar user={user} /></aside><Drawer title="Navigation" open={sidebarOpen} onOpenChange={setSidebarOpen} side="left"><Sidebar user={user} onNavigate={() => setSidebarOpen(false)} /></Drawer><div className="min-w-0 lg:pl-56"><Header user={user} onMenu={() => setSidebarOpen(true)} onLogout={onLogout} signingOut={signingOut} /><main id="main-content" tabIndex={-1} className="mx-auto max-w-[1440px] px-4 py-6 outline-none sm:px-7 sm:py-8">{children}</main><footer className="px-7 pb-5 text-[10px] text-muted-foreground">PWINT THIT <span className="mx-2 text-border">/</span> Distribution management</footer></div></div>
}
