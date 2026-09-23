import { useQuery } from '@tanstack/react-query'
import { ApiError, getJSON } from '@/services/api'

export function useHealth() {
  return useQuery({
    queryKey: ['health'],
    queryFn: async ({ signal }) => {
      const data = await getJSON('/health', signal)
      if (typeof data !== 'object' || data === null || !('status' in data) || data.status !== 'ok' || !('database' in data) || data.database !== 'connected') {
        throw new ApiError('The server returned an unexpected health response.', 200)
      }
      return { status: data.status, database: data.database }
    },
    retry: false,
    refetchInterval: 30_000,
    staleTime: 10_000,
  })
}
