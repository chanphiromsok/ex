import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { OpenManifest } from '#/pages/Manifests'

// Opening a Manifest is a narrower right than reading one.
export const Route = createFileRoute('/_app/manifests/new')({
  beforeLoad: guard('manifests', ['shipment.mark_in_transit']),
  component: Screen,
})

function Screen() {
  const { session } = Route.useRouteContext()
  return <OpenManifest session={session} />
}
