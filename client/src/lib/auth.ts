import { client } from '#/api/client.gen'

export type Session = {
  token: string
  userId: string
  email: string
  role: 'staff' | 'supervisor' | 'admin'
  stationId: string | null
  permissions: string[]
}

const KEY = 'ex.session'

export function getSession(): Session | null {
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? (JSON.parse(raw) as Session) : null
  } catch {
    return null
  }
}

function setSession(session: Session | null) {
  try {
    if (session) localStorage.setItem(KEY, JSON.stringify(session))
    else localStorage.removeItem(KEY)
  } catch {
    // storage blocked: the session just won't survive a reload
  }
}

export function signOut() {
  setSession(null)
}

export async function signIn(email: string, password: string): Promise<Session> {
  const res = await fetch('/api/v1/users/sign-in', {
    method: 'POST',
    headers: {
      'content-type': 'application/vnd.api+json',
      accept: 'application/vnd.api+json',
    },
    body: JSON.stringify({ data: { type: 'user', attributes: { email, password } } }),
  })
  if (!res.ok) throw new Error(res.status === 400 ? 'Wrong email or password' : 'Sign-in failed')
  const body = await res.json()
  const attrs = body.data.attributes
  const session: Session = {
    token: body.meta.token,
    userId: body.data.id,
    email: attrs.email,
    role: attrs.role,
    stationId: attrs.station_id,
    permissions: attrs.permissions ?? [],
  }
  setSession(session)
  return session
}

// Attach the bearer token to every generated-SDK call; a 401 means the token expired.
client.interceptors.request.use((request) => {
  const session = getSession()
  if (session) request.headers.set('authorization', `Bearer ${session.token}`)
  return request
})
client.interceptors.response.use((response) => {
  if (response.status === 401 && getSession()) {
    signOut()
    window.location.assign('/login')
  }
  return response
})
