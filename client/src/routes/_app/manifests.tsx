import { Outlet, createFileRoute } from '@tanstack/react-router'
import { guard } from '#/lib/guard'

export const Route = createFileRoute('/_app/manifests')({
  beforeLoad: guard('manifests'),
  component: Outlet,
})
