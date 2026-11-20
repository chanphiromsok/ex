import axios, { AxiosError, type InternalAxiosRequestConfig } from 'axios'
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

// Plain axios (no interceptors): these calls must not carry a stale bearer or trigger a refresh.
const bare = axios.create({ baseURL: import.meta.env.VITE_API_URL ?? '', headers: HEADERS })

export async function signIn(login: string, password: string): Promise<Session> {
  try {
    const res = await bare.post('/api/v1/users/sign-in', { data: { type: 'user', attributes: { login, password } } })
    const session = toSession(res.data)
    setSession(session)
    return session
  } catch (e) {
    throw new Error(axios.isAxiosError(e) && e.response?.status === 400 ? 'Wrong phone, email or password' : 'Sign-in failed')
  }
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
    try {
      const res = await bare.post('/api/v1/users/refresh', {
        data: { type: 'user', attributes: { refresh_token: current.refreshToken } },
      })
      const session = toSession(res.data)
      setSession(session)
      return session
    } catch {
      return null
    }
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

type Retryable = InternalAxiosRequestConfig & { _retried?: boolean }

// Every call (generated SDK and the helpers in api.ts) goes through this axios instance.
// Requests carry the bearer token. On a 401 the session is refreshed once and the request
// retried; if that fails too, the user is signed out and sent to the login page.
const http = client.instance

http.interceptors.request.use((config) => {
  const session = getSession()
  if (session) config.headers.set('authorization', `Bearer ${session.token}`)
  return config
})

http.interceptors.response.use(undefined, async (error: AxiosError) => {
  const config = error.config as Retryable | undefined
  if (error.response?.status !== 401 || !config) throw error
  const stale = getSession()
  if (!stale || config._retried) {
    if (config?._retried) goToLogin()
    throw error
  }
  const renewed = await refreshSession(stale.token)
  if (!renewed) {
    goToLogin()
    throw error
  }
  config._retried = true
  config.headers.set('authorization', `Bearer ${renewed.token}`)
  return http.request(config)
})

export { http }
