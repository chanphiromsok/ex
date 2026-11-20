import { createFileRoute } from '@tanstack/react-router'
import { Shipments } from '#/pages/Shipments'

export const Route = createFileRoute('/_app/shipments/')({
  // "Show completed" lives in the URL so a filtered list can be shared and survives a reload.
  validateSearch: (s: Record<string, unknown>) => ({ done: s.done === true || s.done === 'true' ? true : undefined }),
  component: Screen,
})

function Screen() {
  const { done } = Route.useSearch()
  const navigate = Route.useNavigate()
  return <Shipments showDone={!!done} onShowDone={(v) => navigate({ search: { done: v ? true : undefined }, replace: true })} />
}
