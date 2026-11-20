import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { CancellationReport } from '#/pages/Reports'

export const Route = createFileRoute('/_app/cancellation-report')({
  beforeLoad: guard('cancellation-report'),
  component: Screen,
})

function Screen() {
  
  return <CancellationReport />
}
