// Sidebar menu. An item shows when the signed-in user holds ANY of its permissions,
// so Permission Overrides change the menu without code changes.
import type { FileRoutesByTo } from '#/routeTree.gen'

export type MenuItem = {
  slug: string
  /** The screen's URL; typed so a renamed route is a compile error here. */
  to: keyof FileRoutesByTo
  label: string
  permissions: string[]
}

export type MenuGroup = { title: string; items: MenuItem[] }

export const MENU: MenuGroup[] = [
  {
    title: 'Counter',
    items: [
      { slug: 'new-shipment', to: '/new-shipment', label: 'New Shipment', permissions: ['shipment.create'] },
      { slug: 'shipments', to: '/shipments', label: 'Shipments', permissions: ['shipment.read'] },
      { slug: 'manifests', to: '/manifests', label: 'Manifests', permissions: ['shipment.mark_in_transit', 'shipment.read'] },
      { slug: 'overdue', to: '/overdue', label: 'Overdue', permissions: ['shipment.read'] },
    ],
  },
  {
    title: 'Follow-up',
    items: [
      {
        slug: 'cancellations',
        to: '/cancellations',
        label: 'Cancellations',
        permissions: ['cancellation.request', 'cancellation.approve'],
      },
      { slug: 'incidents', to: '/incidents', label: 'Incidents', permissions: ['incident.report', 'incident.resolve'] },
    ],
  },
  {
    title: 'Reports',
    items: [
      { slug: 'cash-report', to: '/cash-report', label: 'Cash Report', permissions: ['report.cash'] },
      { slug: 'cancellation-report', to: '/cancellation-report', label: 'Cancellation Report', permissions: ['report.cancellation'] },
    ],
  },
  {
    title: 'Admin',
    items: [
      { slug: 'pricing', to: '/pricing', label: 'Pricing', permissions: ['price.manage'] },
      { slug: 'network', to: '/network', label: 'Stations & Routes', permissions: ['reference_data.manage'] },
      { slug: 'station-settings', to: '/station-settings', label: 'Station Settings', permissions: ['station_setting.manage'] },
      { slug: 'users', to: '/users', label: 'Users', permissions: ['user.manage'] },
    ],
  },
]

export function menuFor(permissions: string[]): MenuGroup[] {
  const held = new Set(permissions)
  return MENU.map((g) => ({
    ...g,
    items: g.items.filter((i) => i.permissions.some((p) => held.has(p))),
  })).filter((g) => g.items.length > 0)
}

export function findItem(slug: string): MenuItem | undefined {
  return MENU.flatMap((g) => g.items).find((i) => i.slug === slug)
}
