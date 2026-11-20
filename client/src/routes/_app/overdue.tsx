import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { Overdue } from '#/pages/FollowUp'

export const Route = createFileRoute('/_app/overdue')({
  beforeLoad: guard('overdue'),
  component: Screen,
})

function Screen() {
  const { session } = Route.useRouteContext()
  return <Overdue session={session} />
}
