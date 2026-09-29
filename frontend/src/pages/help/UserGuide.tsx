import { PageHeader } from '@/components/shared'
import type { CurrentUser } from '@/permissions'
import { visibleNavigation } from '@/components/layout/navigation'
import { guideSections } from './guide'

export default function UserGuide({ current }: { current: CurrentUser }) {
  const available = new Set(visibleNavigation(current).map(item => item.href))
  return <>
    <PageHeader eyebrow="Help / Daily operations" title="User guide" description="From first setup to daily sales, stock checks and business reports." />
    <div className="mb-5 grid gap-3 sm:grid-cols-2">
      {['/dashboard', '/reports'].map(href => available.has(href) && <a key={href} href={href} className="panel p-4 text-sm font-semibold text-primary">{href === '/dashboard' ? 'Open Dashboard' : 'Open Reports'} →</a>)}
    </div>
    <nav aria-label="Guide contents" className="panel mb-6 grid gap-2 p-4 sm:grid-cols-2">{guideSections.map(section => <a key={section.id} href={`#${section.id}`} className="rounded-md p-2 text-xs font-medium hover:bg-muted hover:text-primary">{section.title}</a>)}</nav>
    <div className="space-y-4">{guideSections.map(section => <section key={section.id} id={section.id} className="panel scroll-mt-28 p-5 sm:p-6"><h2 className="mb-3 text-base font-semibold">{section.title}</h2><div className="max-w-4xl space-y-3 text-sm leading-6 text-muted-foreground">{section.paragraphs.map(paragraph => <p key={paragraph}>{paragraph}</p>)}</div>{available.has(section.href) && <a href={section.href} className="mt-4 inline-block text-xs font-semibold text-primary">{section.link} →</a>}</section>)}</div>
  </>
}
