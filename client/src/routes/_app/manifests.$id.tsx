import { createFileRoute } from '@tanstack/react-router'
import { ManifestDetail } from '#/pages/Manifests'

export const Route = createFileRoute('/_app/manifests/$id')({ component: Screen })

function Screen() {
  const { id } = Route.useParams()
  const { session } = Route.useRouteContext()
  return <ManifestDetail id={id} session={session} />
}
