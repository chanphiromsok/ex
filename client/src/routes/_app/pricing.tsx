import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { Pricing } from '#/pages/Pricing'

export const Route = createFileRoute('/_app/pricing')({
  beforeLoad: guard('pricing'),
  component: Screen,
})

function Screen() {
  
  return <Pricing />
}
