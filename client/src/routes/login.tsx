import { useState } from 'react'
import { createFileRoute, redirect, useNavigate } from '@tanstack/react-router'
import { getSession, signIn } from '#/lib/auth'

export const Route = createFileRoute('/login')({
  ssr: false,
  beforeLoad: () => {
    if (getSession()) throw redirect({ to: '/' })
  },
  component: Login,
})

function Login() {
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const data = new FormData(e.currentTarget)
    setBusy(true)
    setError(null)
    try {
      await signIn(String(data.get('email')), String(data.get('password')))
      await navigate({ to: '/' })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign-in failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="grid min-h-screen place-items-center bg-slate-50">
      <form id="login-form" onSubmit={submit} className="w-80 space-y-4 rounded-xl bg-white p-6 shadow">
        <h1 className="text-lg font-semibold">Express Portal</h1>
        <input id="email" name="email" type="email" required placeholder="Email" autoComplete="username"
          className="w-full rounded border border-slate-300 px-3 py-2" />
        <input id="password" name="password" type="password" required placeholder="Password" autoComplete="current-password"
          className="w-full rounded border border-slate-300 px-3 py-2" />
        {error && <p id="login-error" className="text-sm text-red-600">{error}</p>}
        <button id="login-submit" disabled={busy}
          className="w-full rounded bg-slate-900 py-2 text-white transition hover:bg-slate-700 disabled:opacity-50">
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </main>
  )
}
