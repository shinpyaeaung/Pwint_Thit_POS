import type { ReactNode } from 'react'
import { can, type CurrentUser } from '@/permissions'
// Presentation only: Go remains responsible for authorizing every request.
export function PermissionGuard({ user, permission, children, fallback = null }: { user: CurrentUser; permission: string; children: ReactNode; fallback?: ReactNode }) {
  return can(user, permission) ? children : fallback
}
