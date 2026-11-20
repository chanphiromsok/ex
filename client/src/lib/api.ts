import axios from 'axios'
import { http } from '#/lib/auth'

// Minimal JSON:API helper: flattens `{id, attributes}` into one object and
// resolves `included` relationships. Errors become `Error(detail)`.
export type Rec = { id: string; [k: string]: any }
export type Money = { currency: string; amount: string }

async function call(method: string, path: string, body?: unknown): Promise<any> {
  try {
    const res = await http.request({ method, url: path, data: body, responseType: 'json' })
    return res.status === 204 ? null : res.data
  } catch (e) {
    if (!axios.isAxiosError(e) || !e.response) throw e
    const { status, data } = e.response
    const errs: any[] = data?.errors ?? []
    const msg = errs.map((x) => x.detail || x.title).filter(Boolean).join('; ')
    if (status === 403 && (!msg || msg.toLowerCase() === 'forbidden'))
      throw new Error("You're not allowed to do this. Your role may not include it, or this Shipment isn't at your Station. Ask a Supervisor or Admin.")
    throw new Error(msg || `Request failed (${status})`)
  }
}

export function flatten(r: any, included: any[]): Rec {
  const out: Rec = { id: r.id, ...r.attributes }
  for (const [name, rel] of Object.entries<any>(r.relationships ?? {})) {
    const d = rel?.data
    if (!d) continue
    const find = (x: any) => included.find((i) => i.id === x.id && i.type === x.type)
    out[name] = Array.isArray(d)
      ? d.map((x) => find(x)).filter(Boolean).map((x) => flatten(x, included))
      : find(d) ? flatten(find(d), included) : undefined
  }
  return out
}

export async function list(path: string): Promise<Rec[]> {
  const j = await call('GET', path)
  const rows = Array.isArray(j.data) ? j.data : j.data ? [j.data] : []
  return rows.map((r: any) => flatten(r, j.included ?? []))
}
/** One server page: the rows plus the path of the next page (from `links.next`), or null on the last. */
export type Page = { rows: Rec[]; next: string | null }
export async function listPage(path: string): Promise<Page> {
  const j = await call('GET', path)
  const rows = (Array.isArray(j.data) ? j.data : []).map((r: any) => flatten(r, j.included ?? []))
  const link: string | null = j.links?.next ?? null
  // links.next is absolute (http://host/api/v1/shipments?...); keep the path after /api/v1.
  const next = link ? link.replace(/^.*?\/api\/v1/, '') : null
  return { rows, next }
}
export async function get(path: string): Promise<Rec> {
  const j = await call('GET', path)
  return flatten(j.data, j.included ?? [])
}
export async function rawGet(path: string): Promise<any> {
  return call('GET', path)
}
export async function create(path: string, type: string, attributes: object): Promise<Rec> {
  const j = await call('POST', path, { data: { type, attributes } })
  return flatten(j.data, j.included ?? [])
}
export async function update(path: string, type: string, attributes: object): Promise<Rec> {
  const j = await call('PATCH', path, { data: { type, attributes } })
  return flatten(j.data, j.included ?? [])
}
export async function remove(path: string): Promise<void> {
  await call('DELETE', path)
}

export const money = (m?: Money | null) =>
  m ? `${Number(m.amount).toLocaleString('en-US')} ${m.currency === 'KHR' ? '៛' : m.currency}` : '—'
export { when } from './date'
