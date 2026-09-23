import { Button } from '@/components/ui/button'
import { Modal } from './modal'
export function ConfirmDialog({ open, onOpenChange, title, description, onConfirm, confirmLabel = 'Confirm', busy = false, error, destructive = false }: { open: boolean; onOpenChange: (open: boolean) => void; title: string; description: string; onConfirm: () => void; confirmLabel?: string; busy?: boolean; error?: string; destructive?: boolean }) {
  return <Modal open={open} onOpenChange={onOpenChange} title={title} description={description} busy={busy} footer={<><Button variant="outline" disabled={busy} onClick={() => onOpenChange(false)}>Cancel</Button><Button variant={destructive ? 'destructive' : 'default'} disabled={busy} onClick={onConfirm}>{busy ? 'Working…' : confirmLabel}</Button></>}>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : <p className="text-sm text-muted-foreground">Review the details before continuing.</p>}</Modal>
}
