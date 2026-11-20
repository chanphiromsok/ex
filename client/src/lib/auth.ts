import { client } from '#/api/client.gen'
import { formatPhone } from '#/lib/phone'

export type Session = {
  token: string
  /** Single-use secret that buys a new token (and a new refresh token) from /users/refresh. */
  refreshToken: string
  userId: string
  email: string | null
  phone: string | null
  /** What to call this user on screen: the phone if they have one, else the email. */
  label: string
  role: 'staff' | 'supervisor' | 'admin'
  stationId: string | null
  permissions: string[]
}

const KEY = 'ex.session'
// The access token lives one hour, but the refresh token lives 30 days (server side),
// so the cookie lasts as long as the refresh token and the token is renewed on a 401.
const MAX_AGE_SECONDS = 30 * 24 * 60 * 60
const HEADERS = { 'content-type': 'application/vnd.api+json', accept: 'application/vnd.api+json' }

function readCookie(): string | null {
  const hit = document.cookie.split('; ').find((c) => c.startsWith(`${KEY}=`))
  return hit ? decodeURIComponent(hit.slice(KEY.length + 1)) : null
}

function writeCookie(value: string | null) {
  const secure = window.location.protocol === 'https:' ? '; Secure' : ''
  const body = value === null ? '; Max-Age=0' : `; Max-Age=${MAX_AGE_SECONDS}`
  document.cookie = `${KEY}=${value === null ? '' : encodeURIComponent(value)}; Path=/; SameSite=Lax${body}${secure}`
}

export function getSession(): Session | null {
  try {
    const raw = readCookie()
    return raw ? (JSON.parse(raw) as Session) : null
  } catch {
    return null
  }
}

function setSession(session: Session | null) {
  try {
    writeCookie(session ? JSON.stringify(session) : null)
    // Sessions used to live in localStorage; clear any left over from before.
    localStorage.removeItem(KEY)
  } catch {
    // cookies blocked: the session just won't survive a reload
  }
}

export function signOut() {
  setSession(null)
}

// Builds a Session from a sign-in or refresh response (both return the user plus meta tokens).
function toSession(body: any): Session {
  const attrs = body.data.attributes
  return {
    token: body.meta.token,
    refreshToken: body.meta.refresh_token,
    userId: body.data.id,
    email: attrs.email ?? null,
    phone: attrs.phone ?? null,
    label: attrs.phone ? formatPhone(attrs.phone) : attrs.email,
    role: attrs.role,
    stationId: attrs.station_id,
    permissions: attrs.permissions ?? [],
  }
}

export async function signIn(login: string, password: string): Promise<Session> {
  const res = await fetch('/api/v1/users/sign-in', {
    method: 'POST',
    headers: HEADERS,
    body: JSON.stringify({ data: { type: 'user', attributes: { login, password } } }),
  })
  if (!res.ok) throw new Error(res.status === 400 ? 'Wrong phone, email or password' : 'Sign-in failed')
  const session = toSession(await res.json())
  setSession(session)
  return session
}

// Swaps the refresh token for a new session. A refresh token works once, and reusing
// one revokes the whole session, so only one refresh may run at a time: `inFlight`
// covers this tab, the Web Lock covers other tabs. `staleToken` is the token that
// just got a 401; if the cookie already holds a different one, another call or tab
// refreshed first and we use its result.
let inFlight: Promise<Session | null> | null = null

function refreshSession(staleToken: string): Promise<Session | null> {
  inFlight ??= withLock(async () => {
    const current = getSession()
    if (!current?.refreshToken) return null
    if (current.token !== staleToken) return current
    const res = await fetch('/api/v1/users/refresh', {
      method: 'POST',
      headers: HEADERS,
      body: JSON.stringify({ data: { type: 'user', attributes: { refresh_token: current.refreshToken } } }),
    }).catch(() => null)
    if (!res?.ok) return null
    const session = toSession(await res.json())
    setSession(session)
    return session
  }).finally(() => {
    inFlight = null
  })
  return inFlight
}

function withLock<T>(fn: () => Promise<T>): Promise<T> {
  return navigator.locks ? navigator.locks.request('ex.refresh', fn) : fn()
}

function goToLogin() {
  signOut()
  window.location.assign('/login')
}

/**
 * `fetch` with the bearer token. On a 401 it refreshes the session once and retries;
 * if that fails too, the user is signed out and sent to the login page.
 */
export async function authFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const request = new Request(input, init)
  const session = getSession()
  if (!session) return fetch(request)
  const retry = request.clone()
  request.headers.set('authorization', `Bearer ${session.token}`)
  const res = await fetch(request)
  if (res.status !== 401) return res

  const renewed = await refreshSession(session.token)
  if (!renewed) {
    goToLogin()
    return res
  }
  retry.headers.set('authorization', `Bearer ${renewed.token}`)
  const second = await fetch(retry)
  if (second.status === 401) goToLogin()
  return second
}

// Every generated-SDK call goes through authFetch.
client.setConfig({ fetch: authFetch as typeof fetch })
