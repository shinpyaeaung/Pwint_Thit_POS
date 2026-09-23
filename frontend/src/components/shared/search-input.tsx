import { Search, X } from 'lucide-react'
import { useId } from 'react'
import { Button } from '@/components/ui/button'
export function SearchInput({ value, onValueChange, label = 'Search records', placeholder = 'Search records…' }: { value: string; onValueChange: (value: string) => void; label?: string; placeholder?: string }) {
  const id = useId()
  return <div className="relative min-w-0 flex-1 basis-full sm:basis-60 sm:max-w-sm"><label htmlFor={id} className="sr-only">{label}</label><Search aria-hidden="true" className="pointer-events-none absolute left-3 top-3 size-4 text-muted-foreground" /><input id={id} type="search" className="field h-10 pl-9 pr-10 [&::-webkit-search-cancel-button]:appearance-none" value={value} onChange={e => onValueChange(e.target.value)} placeholder={placeholder} />{value && <Button type="button" variant="ghost" size="icon-sm" aria-label={`Clear ${label.toLowerCase()}`} className="absolute right-1 top-1" onClick={() => onValueChange('')}><X /></Button>}</div>
}
