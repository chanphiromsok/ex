import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { Incidents } from '#/pages/FollowUp'

export const Route = createFileRoute('/_app/incidents')({
  beforeLoad: guard('incidents'),
  component: Screen,
})

function Screen() {
  const { session } = Route.useRouteContext()
  return <Incidents session={session} />
}
