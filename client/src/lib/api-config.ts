import type { CreateClientConfig } from '#/api/client.gen'

// Where the browser sends API calls. Empty means same origin (dev: Vite proxies /api).
// Production builds read VITE_API_URL from client/.env.production.
export const createClientConfig: CreateClientConfig = (config) => ({
  ...config,
  baseUrl: import.meta.env.VITE_API_URL ?? '',
})
