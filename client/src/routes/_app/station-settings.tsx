import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { StationSettings } from '#/pages/Admin'

export const Route = createFileRoute('/_app/station-settings')({
  beforeLoad: guard('station-settings'),
  component: Screen,
})

function Screen() {
  
  return <StationSettings />
}
