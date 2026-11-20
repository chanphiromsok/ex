import type { CreateClientConfig } from '#/api/client.gen'

// JSON:API nests query params (filter[status][in][]=x, page[after]=y). The generated
// serializer only goes one level deep, so walk the whole object here.
export function serializeQuery(query: Record<string, unknown>): string {
  const out: string[] = []
  const walk = (key: string, value: unknown) => {
    if (value === undefined || value === null) return
    if (Array.isArray(value)) value.forEach((v) => walk(`${key}[]`, v))
    else if (typeof value === 'object') for (const [k, v] of Object.entries(value)) walk(`${key}[${k}]`, v)
    else out.push(`${encodeURIComponent(key).replace(/%5B/g, '[').replace(/%5D/g, ']')}=${encodeURIComponent(String(value))}`)
  }
  for (const [k, v] of Object.entries(query)) walk(k, v)
  return out.join('&')
}

// Where the browser sends API calls. Empty means same origin (dev: Vite proxies /api).
// Production builds read VITE_API_URL from client/.env.production.
export const createClientConfig: CreateClientConfig = (config) => ({
  ...config,
  headers: { 'Content-Type': 'application/vnd.api+json', Accept: 'application/vnd.api+json' },
  baseURL: `${import.meta.env.VITE_API_URL ?? ''}/api/v1`,
  querySerializer: serializeQuery,
})
