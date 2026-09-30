import { useSidebarScroll } from '@/hooks/use-sidebar-scroll'
import { Sprout } from 'lucide-react'
import { can, type CurrentUser } from '@/permissions'
import { guideLink, navigationGroups, overviewLinks, type NavigationItem } from './navigation'

export function Sidebar({ user, onNavigate }: { user: CurrentUser; onNavigate?: () => void }) {
  const scroll = useSidebarScroll(user.id, !!onNavigate)
  const overview = overviewLinks.filter(item => can(user, item.permission))
  const groups = navigationGroups.map(group => ({ ...group, items: group.items.filter(item => can(user, item.permission)) })).filter(group => group.items.length)
  function link(item: NavigationItem) {
    const path = window.location.pathname
    const active = path === item.href || path.startsWith(`${item.href}/`) || (item.href === '/dashboard' && path === '/')
    return <a key={item.href} href={item.href} onClick={onNavigate} aria-current={active ? 'page' : undefined} className={`flex min-h-10 items-center gap-3 rounded-lg px-3 py-2 text-[13px] font-medium transition-colors ${active ? 'bg-primary/7 text-primary ring-1 ring-primary/10' : 'text-muted-foreground hover:bg-muted hover:text-foreground'}`}><item.icon aria-hidden="true" className="size-4 shrink-0" /><span>{item.label}</span>{active && <span aria-hidden="true" className="ml-auto size-1.5 shrink-0 rounded-full bg-primary" />}</a>
  }
  return <div className="flex h-full min-h-0 flex-1 flex-col overflow-hidden">
    <a href="/" onClick={onNavigate} className="flex shrink-0 items-center gap-3 px-5 py-5" aria-label="Pwint Thit home"><span className="rounded-xl bg-primary p-2 text-white"><Sprout className="size-5" /></span><span><span className="block text-sm font-bold tracking-wide">PWINT THIT</span><span className="mt-0.5 block text-[9px] font-medium tracking-[0.22em] text-muted-foreground">DISTRIBUTION</span></span></a>
    {overview.length > 0 && <nav aria-label="Business overview" className="shrink-0 space-y-1 border-b px-3 pb-3">{overview.map(link)}</nav>}
    <nav {...scroll} aria-label="Main navigation" tabIndex={0} className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-3 pb-4 focus-visible:outline-offset-[-2px]" style={{ scrollbarGutter: 'stable', scrollbarWidth: 'thin' }}>
      {groups.map(group => <section key={group.title} aria-label={group.title} className="pt-4"><h2 className="px-3 pb-2 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">{group.title}</h2><div className="space-y-0.5">{group.items.map(link)}</div></section>)}
      {groups.length === 0 && <p className="px-3 py-4 text-xs leading-5 text-muted-foreground">Ask your Super Admin to assign the tools you need.</p>}
    </nav>
    <div className="shrink-0 border-t p-3">{link(guideLink)}</div>
  </div>
}
