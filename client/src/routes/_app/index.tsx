import { Link, createFileRoute } from '@tanstack/react-router'
import { ChevronRight } from 'lucide-react'
import { menuFor } from '#/lib/menu'
import { SCREEN_META } from '#/components/nav'
import { Page } from '#/components/kit'

export const Route = createFileRoute('/_app/')({ component: Home })

function Home() {
  const { session } = Route.useRouteContext()
  const groups = menuFor(session.permissions)
  const name = session.email.split('@')[0]

  return (
    <Page title={`Hello, ${name}`} subtitle={<span className="capitalize">{session.role}</span>}>
      <div className="grid gap-5 md:grid-cols-2">
        {groups.map((g) => (
          <section key={g.title} className="overflow-hidden rounded-weave border border-thread bg-surface">
            <h2 className="border-b border-thread px-5 py-3 text-[13px] font-medium text-ink-soft">{g.title}</h2>
            <ul>
              {g.items.map((i) => {
                const meta = SCREEN_META[i.slug]
                const Icon = meta?.icon
                return (
                  <li key={i.slug} className="border-t border-thread first:border-t-0">
                    <Link
                      to="/$page"
                      params={{ page: i.slug }}
                      className="group flex items-center gap-3.5 px-5 py-3.5 transition-colors hover:bg-clay-wash/50"
                    >
                      {Icon && (
                        <span className="grid size-9 shrink-0 place-items-center rounded-weave bg-clay-wash text-clay">
                          <Icon aria-hidden className="size-[18px]" />
                        </span>
                      )}
                      <span className="min-w-0 flex-1">
                        <span className="block text-sm font-medium text-ink">{i.label}</span>
                        {meta && <span className="block truncate text-[13px] text-ink-soft">{meta.blurb}</span>}
                      </span>
                      <ChevronRight aria-hidden className="size-4 shrink-0 text-ink-faint transition-transform duration-200 ease-out-expo group-hover:translate-x-0.5" />
                    </Link>
                  </li>
                )
              })}
            </ul>
          </section>
        ))}
      </div>
    </Page>
  )
}
