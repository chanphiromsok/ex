import type { Query } from '@tanstack/react-query'
import { flatten, type Rec } from './api'

/**
 * Queries come from the generated options in `#/api/@tanstack/react-query.gen`
 * (`getStationsOptions()`, `getShipmentsByIdOptions({ path: { id } })`, ...). The API
 * speaks JSON:API; `asRows` / `asRow` are their `select` to get flat records the pages use:
 *
 *   useQuery({ ...getStationsOptions(), select: asRows })
 */
export const asRows = (r: any): Rec[] => {
  const data = Array.isArray(r) ? r : Array.isArray(r?.data) ? r.data : r?.data ? [r.data] : []
  return data.map((d: any) => flatten(d, r?.included ?? []))
}
export const asRow = (r: any): Rec => flatten(r.data, r.included ?? [])

/**
 * Invalidates every generated query for a resource. Generated keys are
 * `[{ _id: 'getShipmentsById', ... }]`, so 'shipments' matches getShipments,
 * getShipmentsById, getShipmentsOverdue (list and infinite) but not getShipmentNotes.
 *
 *   qc.invalidateQueries(resource('shipments'))
 */
const norm = (s: string) => s.replace(/[^a-z]/gi, '').toLowerCase()
export const resource = (name: string) => ({
  predicate: (q: Query) => {
    const id = (q.queryKey[0] as { _id?: string } | undefined)?._id
    return !!id && norm(id.replace(/^(get|post|patch|delete)/, '')).startsWith(norm(name))
  },
})

/** The server's next cursor, from the last page's `links.next` (`page[after]=...`). */
export const nextCursor = (last: any) => {
  const next = last?.links?.next
  const after = next ? new URL(next, location.origin).searchParams.get('page[after]') : null
  return after ? { query: { page: { after } } } : undefined
}
