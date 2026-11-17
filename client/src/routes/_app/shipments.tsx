import { Outlet, createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'

// Layout for every /shipments screen: one permission check covers the list and the detail.
export const Route = createFileRoute('/_app/shipments')({
  beforeLoad: guard('shipments'),
  component: Outlet,
})
