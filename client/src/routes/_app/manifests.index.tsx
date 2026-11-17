import { createFileRoute } from '@tanstack/react-router'
import { Manifests } from '#/pages/Manifests'

export const Route = createFileRoute('/_app/manifests/')({ component: Screen })

function Screen() {
  const { session } = Route.useRouteContext()
  return <Manifests session={session} />
}
