import { useQuery } from '@tanstack/react-query'
import { ApiError, requestJSON } from '@/services/api'
import type { CurrentUser } from '@/permissions'
export function useSession() {
  return useQuery({ queryKey: ['session'], queryFn: async ({ signal }): Promise<CurrentUser | null> => {
    try { return (await requestJSON<{ user: CurrentUser }>('/auth/me', { signal })).user }
    catch (error) { if (error instanceof ApiError && error.status === 401) return null; throw error }
  }, retry: false, staleTime: 0, refetchInterval: 30_000, refetchOnWindowFocus: 'always' })
}
