import { queryOptions } from '@tanstack/react-query'
import { get, list, rawGet } from './api'

/**
 * Query keys follow the API path: '/shipments/42?include=parcels' becomes
 * ['api', 'shipments', '42', 'include=parcels', <kind>]. Invalidating a prefix
 * such as `apiKey('shipments')` therefore refreshes the list and every detail.
 */
export const apiKey = (...parts: string[]) => ['api', ...parts]

function keyFor(path: string, kind: 'list' | 'one' | 'raw') {
  const [p, q] = path.split('?')
  const parts = p.split('/').filter(Boolean)
  return [...apiKey(...parts), ...(q ? [q] : []), kind]
}

export const listQuery = (path: string) => queryOptions({ queryKey: keyFor(path, 'list'), queryFn: () => list(path) })

export const recordQuery = (path: string) => queryOptions({ queryKey: keyFor(path, 'one'), queryFn: () => get(path) })

export const rawQuery = <T = any>(path: string) =>
  queryOptions({ queryKey: keyFor(path, 'raw'), queryFn: () => rawGet(path) as Promise<T> })
