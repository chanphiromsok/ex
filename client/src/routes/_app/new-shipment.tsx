import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { NewShipment } from '#/pages/NewShipment'

export const Route = createFileRoute('/_app/new-shipment')({
  beforeLoad: guard('new-shipment'),
  component: Screen,
})

function Screen() {
  const { session } = Route.useRouteContext()
  return <NewShipment stationId={session.stationId} />
}
