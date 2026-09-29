import { PageHeader } from '@/components/shared'
import type { CurrentUser } from '@/permissions'
import { visibleNavigation } from '@/components/layout/navigation'
export default function Home({ current }: { current: CurrentUser }) {
  const links = visibleNavigation(current)
  return <><PageHeader eyebrow="Start here" title="Your workspace" description="Choose a tool to start work. Your Super Admin controls which tools you can access." />
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{links.map(item => <a key={item.href} href={item.href} className="panel flex items-center gap-3 p-5 text-sm font-medium hover:border-primary/30"><item.icon className="size-5 text-primary" />{item.label}</a>)}</div>
    {!links.length && <p className="panel p-5 text-sm">No business tools have been assigned yet. Ask your Super Admin to open Users & access and grant your permissions.</p>}
    <div className="mt-5 rounded-xl border border-amber-200 bg-amber-50 p-5 text-sm leading-6"><h2 className="font-semibold">Looking for Dashboard or Reports?</h2><p>These pages need separate access. Reports also needs permission for the business information you want to read.</p><a href="/guide#access" className="mt-2 inline-block font-medium text-primary">Read the access guide →</a></div>
    <a href="/guide" className="mt-5 inline-block text-sm font-medium text-primary">Open the user guide →</a>
  </>
}
