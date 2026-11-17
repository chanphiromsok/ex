import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { Network } from '#/pages/Network'

export const Route = createFileRoute('/_app/network')({
  beforeLoad: guard('network'),
  component: Screen,
})

function Screen() {
  
  return <Network />
}
