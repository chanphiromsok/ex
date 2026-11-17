import { Link, Outlet, createFileRoute, redirect, useNavigate } from '@tanstack/react-router'
import { getSession, signOut } from '#/lib/auth'
import { menuFor } from '#/lib/menu'

export const Route = createFileRoute('/_app')({
  ssr: false,
  beforeLoad: () => {
    const session = getSession()
    if (!session) throw redirect({ to: '/login' })
    return { session }
  },
  component: Shell,
})

function Shell() {
  const { session } = Route.useRouteContext()
  const navigate = useNavigate()
  const groups = menuFor(session.permissions)

  return (
    <div className="flex min-h-screen">
      <aside id="sidebar" className="flex w-60 shrink-0 flex-col border-r border-slate-200 bg-slate-900 text-slate-200">
        <Link to="/" className="px-5 py-4 text-lg font-semibold text-white">Express Portal</Link>
        <nav className="flex-1 space-y-5 overflow-y-auto px-3 pb-4">
          {groups.map((g) => (
            <div key={g.title}>
              <p className="px-2 pb-1 text-xs uppercase tracking-wide text-slate-500">{g.title}</p>
              {g.items.map((i) => (
                <Link key={i.slug} id={`menu-${i.slug}`} to="/$page" params={{ page: i.slug }}
                  className="block rounded px-2 py-1.5 text-sm transition hover:bg-slate-800"
                  activeProps={{ className: 'bg-slate-700 text-white' }}>
                  {i.label}
                </Link>
              ))}
            </div>
          ))}
        </nav>
        <div className="border-t border-slate-800 p-4 text-xs">
          <p className="truncate">{session.email}</p>
          <p className="capitalize text-slate-500">{session.role}</p>
          <button id="sign-out"
            onClick={async () => { signOut(); await navigate({ to: '/login' }) }}
            className="mt-2 text-slate-400 underline transition hover:text-white">
            Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 bg-slate-50 p-8"><Outlet /></main>
    </div>
  )
}
