import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/_app/')({ component: Home })

function Home() {
  const { session } = Route.useRouteContext()
  return (
    <section>
      <h1 className="text-xl font-semibold">Welcome</h1>
      <p className="mt-2 text-slate-600">Signed in as {session.email} ({session.role}). Pick a menu item to start.</p>
    </section>
  )
}
