import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { CashReport } from '#/pages/Reports'

export const Route = createFileRoute('/_app/cash-report')({
  beforeLoad: guard('cash-report'),
  component: Screen,
})

function Screen() {
  
  return <CashReport />
}
