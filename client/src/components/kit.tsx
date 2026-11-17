import { useState, type ReactNode } from 'react'

export const input = 'w-full rounded border border-slate-300 bg-white px-3 py-1.5 text-sm outline-none transition focus:border-slate-500'
export const btn = 'rounded bg-slate-900 px-3 py-1.5 text-sm text-white transition hover:bg-slate-700 disabled:opacity-50'
export const btn2 = 'rounded border border-slate-300 px-3 py-1.5 text-sm transition hover:bg-slate-100 disabled:opacity-50'

export function Page({ title, children, action }: { title: string; children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mx-auto max-w-5xl space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">{title}</h1>
        {action}
      </div>
      {children}
    </div>
  )
}

export function Card({ children, title }: { children: ReactNode; title?: string }) {
  return (
    <section className="space-y-3 rounded-lg border border-slate-200 bg-white p-4">
      {title && <h2 className="text-sm font-medium text-slate-500">{title}</h2>}
      {children}
    </section>
  )
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block space-y-1 text-sm">
      <span className="text-slate-600">{label}</span>
      {children}
    </label>
  )
}

export function Err({ error }: { error: unknown }) {
  if (!error) return null
  return <p role="alert" className="rounded bg-red-50 px-3 py-2 text-sm text-red-700">{(error as Error).message}</p>
}

export function Table({ head, rows, empty = 'Nothing here yet.' }: { head: string[]; rows: ReactNode[][]; empty?: string }) {
  if (rows.length === 0) return <p className="text-sm text-slate-500">{empty}</p>
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead className="text-xs uppercase text-slate-500">
          <tr>{head.map((h) => <th key={h} className="px-2 py-1.5 font-medium">{h}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="border-t border-slate-100">
              {r.map((c, j) => <td key={j} className="px-2 py-1.5">{c}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// Runs an async action, tracking busy + error state for a button/form.
export function useAction<T extends unknown[]>(fn: (...a: T) => Promise<unknown>, after?: () => void) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<unknown>(null)
  const run = async (...a: T) => {
    setBusy(true)
    setError(null)
    try {
      await fn(...a)
      after?.()
    } catch (e) {
      setError(e)
    } finally {
      setBusy(false)
    }
  }
  return { run, busy, error }
}
