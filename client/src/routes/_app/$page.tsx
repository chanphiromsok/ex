import { createFileRoute, notFound } from '@tanstack/react-router'
import type { ReactNode } from 'react'
import { findItem } from '#/lib/menu'
import type { Session } from '#/lib/auth'
import { NewShipment } from '#/pages/NewShipment'
import { Shipments } from '#/pages/Shipments'
import { Manifests } from '#/pages/Manifests'
import { Overdue, Cancellations, Incidents } from '#/pages/FollowUp'
import { CashReport, CancellationReport } from '#/pages/Reports'
import { Pricing } from '#/pages/Pricing'
import { Network } from '#/pages/Network'
import { StationSettings, Users } from '#/pages/Admin'

const SCREENS: Record<string, (s: Session) => ReactNode> = {
  'new-shipment': (s) => <NewShipment stationId={s.stationId} />,
  shipments: (s) => <Shipments session={s} />,
  manifests: (s) => <Manifests session={s} />,
  overdue: (s) => <Overdue session={s} />,
  cancellations: (s) => <Cancellations session={s} />,
  incidents: (s) => <Incidents session={s} />,
  'cash-report': () => <CashReport />,
  'cancellation-report': () => <CancellationReport />,
  pricing: () => <Pricing />,
  network: () => <Network />,
  'station-settings': () => <StationSettings />,
  users: () => <Users />,
}

export const Route = createFileRoute('/_app/$page')({
  beforeLoad: ({ params, context }) => {
    const item = findItem(params.page)
    if (!item || !item.permissions.some((p) => context.session.permissions.includes(p))) throw notFound()
    return { item }
  },
  component: Page,
})

function Page() {
  const { item, session } = Route.useRouteContext()
  const screen = SCREENS[item.slug]
  return screen ? <>{screen(session)}</> : <p className="text-ink-soft">No screen for {item.label}.</p>
}
