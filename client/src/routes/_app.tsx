import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link, Outlet, createFileRoute, redirect, useNavigate } from '@tanstack/react-router'
import { LogOut, Menu, X } from 'lucide-react'
import { getSession, signOut } from '#/lib/auth'
import { menuFor } from '#/lib/menu'
import { listQuery } from '#/lib/queries'
import { BrandMark, SCREEN_META, StationIcon } from '#/components/nav'

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
  const { session, queryClient } = Route.useRouteContext()
  const navigate = useNavigate()
  const groups = menuFor(session.permissions)
  const [open, setOpen] = useState(false)
  const stations = useQuery({ ...listQuery('/stations'), enabled: !!session.stationId })
  const station = stations.data?.find((s) => s.id === session.stationId)

  const rail = (
    <>
      <Link to="/" onClick={() => setOpen(false)} className="flex h-16 items-center gap-2.5 px-5 text-on-rail">
        <BrandMark className="size-5 text-clay" />
        <span className="font-serif text-[17px] font-medium tracking-[-0.01em]">Express Cargo</span>
      </Link>

      <nav aria-label="Main" className="flex-1 space-y-6 overflow-y-auto px-3 pb-6 pt-2">
        {groups.map((g) => (
          <div key={g.title}>
            <p className="px-2.5 pb-1.5 text-xs font-medium text-on-rail-soft">{g.title}</p>
            <ul className="space-y-0.5">
              {g.items.map((i) => {
                const Icon = SCREEN_META[i.slug]?.icon
                return (
                  <li key={i.slug}>
                    <Link
                      id={`menu-${i.slug}`}
                      to={i.to}
                      onClick={() => setOpen(false)}
                      className="group relative flex h-9 items-center gap-2.5 rounded-md px-2.5 text-sm text-on-rail/80 transition-colors duration-150 hover:bg-rail-line/60 hover:text-on-rail"
                      activeProps={{ className: '!bg-rail-line !text-on-rail font-medium' }}
                    >
                      {Icon && <Icon aria-hidden className="size-4 shrink-0 opacity-75 group-data-[status=active]:text-clay group-data-[status=active]:opacity-100" />}
                      <span className="truncate">{i.label}</span>
                    </Link>
                  </li>
                )
              })}
            </ul>
          </div>
        ))}
      </nav>

      <div className="border-t border-rail-line px-4 py-4">
        <p className="truncate text-[13px] font-medium text-on-rail">{session.label}</p>
        <p className="mt-0.5 flex items-center gap-1.5 truncate text-xs text-on-rail-soft">
          <span className="capitalize">{session.role}</span>
          {station && (
            <>
              <span aria-hidden>·</span>
              <StationIcon aria-hidden className="size-3 shrink-0" />
              <span className="truncate">{station.name_en}</span>
            </>
          )}
        </p>
        <button
          id="sign-out"
          type="button"
          onClick={async () => {
            signOut()
            queryClient.clear()
            await navigate({ to: '/login' })
          }}
          className="-ml-2 mt-3 inline-flex h-8 items-center gap-2 rounded-md px-2 text-[13px] text-on-rail-soft transition-colors hover:bg-rail-line/60 hover:text-on-rail"
        >
          <LogOut aria-hidden className="size-3.5" />
          Sign out
        </button>
      </div>
    </>
  )

  return (
    <div className="min-h-screen lg:flex">
      {/* Narrow screens: a slim bar that opens the rail. */}
      <div className="no-print sticky top-0 z-30 flex h-14 items-center justify-between border-b border-rail-line bg-rail px-4 text-on-rail lg:hidden">
        <Link to="/" className="flex items-center gap-2">
          <BrandMark className="size-[18px] text-clay" />
          <span className="font-serif text-[15px] font-medium">Express Cargo</span>
        </Link>
        <button
          type="button"
          aria-label={open ? 'Close menu' : 'Open menu'}
          aria-expanded={open}
          onClick={() => setOpen(!open)}
          className="grid size-9 place-items-center rounded-md hover:bg-rail-line"
        >
          {open ? <X className="size-5" /> : <Menu className="size-5" />}
        </button>
      </div>

      <aside
        id="sidebar"
        className={`no-print fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-rail-line bg-rail transition-transform duration-300 ease-out-expo lg:sticky lg:top-0 lg:h-screen lg:w-60 lg:shrink-0 lg:translate-x-0 ${open ? 'translate-x-0 shadow-2xl' : '-translate-x-full'}`}
      >
        {rail}
      </aside>
      {open && <button type="button" aria-label="Close menu" className="fixed inset-0 z-30 bg-ink/25 lg:hidden" onClick={() => setOpen(false)} />}

      <main className="min-w-0 flex-1">
        <Outlet />
      </main>
    </div>
  )
}
