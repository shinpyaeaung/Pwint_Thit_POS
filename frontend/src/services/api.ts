export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) { super(message); this.name = 'ApiError'; this.status = status }
}

export async function requestJSON<T>(path: string, options: RequestInit = {}): Promise<T> {
  let response: Response
  try {
    response = await fetch(`/api/v1${path}`, {
      ...options, credentials: 'same-origin',
      headers: { Accept: 'application/json', ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        ...(options.method && options.method !== 'GET' ? { 'X-Pwint-Thit-Request': '1' } : {}), ...options.headers },
    })
  } catch (error) {
    if (options.signal?.aborted) throw error
    throw new ApiError('Unable to reach the server. Check the connection and try again.', 0)
  }
  if (!response.ok) {
    const body = await response.json().catch(() => null)
    throw new ApiError(body?.error?.message || 'The server is unavailable. Please try again.', response.status)
  }
  if (response.status === 204) return undefined as T
  return response.json() as Promise<T>
}
export const getJSON = (path: string, signal?: AbortSignal): Promise<unknown> => requestJSON(path, { signal })
