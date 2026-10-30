export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) { super(message); this.name = 'ApiError'; this.status = status }
}

export async function requestJSON<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers)
  if (!headers.has('Accept')) headers.set('Accept', 'application/json')
  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json')
  if (options.method && !['GET', 'HEAD', 'OPTIONS'].includes(options.method.toUpperCase())) headers.set('X-Pwint-Thit-Request', '1')
  let response: Response
  try {
    response = await fetch(`/api/v1${path}`, {
      ...options, credentials: 'same-origin', headers,
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
  try {
    return await response.json() as T
  } catch (error) {
    if (options.signal?.aborted) throw error
    // A write may already have committed. Keep checkout's same-request retry
    // protection active when the success body is truncated or unreadable.
    throw new ApiError('The server response could not be read. Retry the same request to confirm its result.', 502)
  }
}
export const getJSON = (path: string, signal?: AbortSignal): Promise<unknown> => requestJSON(path, { signal })
