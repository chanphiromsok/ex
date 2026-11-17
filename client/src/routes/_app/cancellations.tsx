import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { Cancellations } from '#/pages/FollowUp'

export const Route = createFileRoute('/_app/cancellations')({
  beforeLoad: guard('cancellations'),
  component: Screen,
})

function Screen() {
  const { session } = Route.useRouteContext()
  return <Cancellations session={session} />
}
