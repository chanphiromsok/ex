import { getSession, signOut } from '#/lib/auth'

// Minimal JSON:API helper: flattens `{id, attributes}` into one object and
// resolves `included` relationships. Errors become `Error(detail)`.
export type Rec = { id: string; [k: string]: any }
export type Money = { currency: string; amount: string }

const HEADERS = { 'content-type': 'application/vnd.api+json', accept: 'application/vnd.api+json' }

async function call(method: string, path: string, body?: unknown): Promise<any> {
  const session = getSession()
  const res = await fetch(`/api/v1${path}`, {
    method,
    headers: { ...HEADERS, ...(session ? { authorization: `Bearer ${session.token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (res.status === 401 && session) {
    signOut()
    window.location.assign('/login')
  }
  if (res.status === 204) return null
  const json = await res.json().catch(() => null)
  if (!res.ok) {
    const errs: any[] = json?.errors ?? []
    const msg = errs.map((e) => e.detail || e.title).filter(Boolean).join('; ')
    throw new Error(msg || `Request failed (${res.status})`)
  }
  return json
}

function flatten(r: any, included: any[]): Rec {
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
