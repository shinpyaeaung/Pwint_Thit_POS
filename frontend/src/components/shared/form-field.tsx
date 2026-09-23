import { useId, type ReactNode } from 'react'
type ControlProps = { id: string; 'aria-describedby'?: string; 'aria-invalid'?: true; required?: boolean }
export function FormField({ label, hint, error, required, children }: { label: string; hint?: string; error?: string; required?: boolean; children: (props: ControlProps) => ReactNode }) {
  const id = useId()
  return <div className="min-w-0 space-y-2"><div className="flex items-center text-xs font-medium"><label htmlFor={id}>{label}</label>{required && <span aria-hidden="true" className="ml-1 text-primary">*</span>}</div>{children({ id, 'aria-describedby': error || hint ? `${id}-help` : undefined, 'aria-invalid': error ? true : undefined, required })}{(error || hint) && <p id={`${id}-help`} role={error ? 'alert' : undefined} className={`text-xs leading-5 ${error ? 'text-destructive' : 'text-muted-foreground'}`}>{error || hint}</p>}</div>
}
