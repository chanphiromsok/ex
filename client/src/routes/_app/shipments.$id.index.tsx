import { createFileRoute } from '@tanstack/react-router'
import { ShipmentDetail } from '#/pages/Shipments'

export const Route = createFileRoute('/_app/shipments/$id/')({ component: Screen })

function Screen() {
  const { id } = Route.useParams()
  const { session } = Route.useRouteContext()
  return <ShipmentDetail id={id} session={session} />
}
