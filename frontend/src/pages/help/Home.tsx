import { PageHeader } from '@/components/shared'
import type { CurrentUser } from '@/permissions'
import { visibleNavigation } from '@/components/layout/navigation'
import { ArrowRight, HelpCircle } from 'lucide-react'

export default function Home({ current }: { current: CurrentUser }) {
  const links = visibleNavigation(current)
  return <>
    <PageHeader eyebrow="Start here" title="Your workspace" description="Choose a tool to start work. Your Super Admin controls which tools you can access." />
    
    <div className="grid gap-x-6 sm:grid-cols-2 lg:grid-cols-3">
      {links.map(item => (
        <a key={item.href} href={item.href} className="border-b group flex items-center justify-between py-4 text-sm font-semibold text-foreground transition-colors duration-150 hover:border-border  ">
          <div className="flex items-center gap-3.5 min-w-0">
            <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-muted text-muted-foreground transition-colors group-hover:bg-primary/10 group-hover:text-primary">
              <item.icon className="size-5" />
            </span>
            <span className="truncate">{item.label}</span>
          </div>
          <ArrowRight className="size-4 shrink-0 text-stone-300 transition-transform duration-150 group-hover:translate-x-0.5 group-hover:text-primary" />
        </a>
      ))}
    </div>

    {!links.length && (
      <div className="panel p-8 text-center text-sm text-muted-foreground">
        No business tools have been assigned yet. Ask your Super Admin to open Users & access and grant your permissions.
      </div>
    )}

    <div className="mt-8 rounded-lg border border-amber-200/80 bg-amber-50 p-6 ">
      <div className="flex items-start gap-4">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-amber-100 text-amber-800">
          <HelpCircle className="size-5" />
        </span>
        <div>
          <h2 className="text-sm font-semibold text-amber-950">Looking for Dashboard or Reports?</h2>
          <p className="mt-1 text-xs leading-5 text-amber-900">These pages need separate access. Reports also needs permission for the business information you want to read.</p>
          <a href="/guide#access" className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline">Read the access guide →</a>
        </div>
      </div>
    </div>

    <div className="mt-6">
      <a href="/guide" className="inline-flex items-center gap-1.5 text-xs font-semibold text-primary hover:underline">
        Open the user guide <ArrowRight className="size-3.5" />
      </a>
    </div>
  </>
}

