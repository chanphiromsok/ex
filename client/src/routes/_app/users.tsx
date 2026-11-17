import { createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'
import { Users } from '#/pages/Admin'

export const Route = createFileRoute('/_app/users')({
  beforeLoad: guard('users'),
  component: Screen,
})

function Screen() {
  
  return <Users />
}
