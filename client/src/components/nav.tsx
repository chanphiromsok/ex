import {
  AlarmClock,
  Ban,
  Building2,
  ClipboardList,
  ChartColumn,
  FileX,
  Network,
  PackagePlus,
  Receipt,
  Search,
  Settings2,
  TriangleAlert,
  Users,
  type LucideIcon,
} from 'lucide-react'

/** Icon and one-line purpose for each menu slug in lib/menu.ts. */
export const SCREEN_META: Record<string, { icon: LucideIcon; blurb: string }> = {
  'new-shipment': { icon: PackagePlus, blurb: 'Take Parcels and Payment, issue an Invoice Number.' },
  shipments: { icon: Search, blurb: 'Find a Shipment by Invoice Number or phone and move it on.' },
  manifests: { icon: ClipboardList, blurb: 'Open a Trip, load Shipments, mark the bus left, unload on arrival.' },
  overdue: { icon: AlarmClock, blurb: 'Arrived Shipments waiting too long for Collection.' },
  cancellations: { icon: Ban, blurb: 'Cancellation requests and their decisions.' },
  incidents: { icon: TriangleAlert, blurb: 'Lost, damaged, redirected or returned Shipments.' },
  'cash-report': { icon: Receipt, blurb: 'Cash taken and refunded, per staff member.' },
  'cancellation-report': { icon: FileX, blurb: 'Cancellations, refunds and fees kept.' },
  pricing: { icon: ChartColumn, blurb: 'Price per kg, Size Classes, Sale Items and fees.' },
  network: { icon: Network, blurb: 'Locations, Stations and the Routes between them.' },
  'station-settings': { icon: Settings2, blurb: 'Cancellation approval and Overdue threshold.' },
  users: { icon: Users, blurb: 'Staff accounts, roles and Stations.' },
}

export const StationIcon = Building2

export function BrandMark({ className = '' }: { className?: string }) {
  // Two crossed threads: the krama check, at its smallest.
  return (
    <svg viewBox="0 0 20 20" aria-hidden className={className}>
      <rect x="0" y="7" width="20" height="6" rx="1.5" fill="currentColor" opacity="0.55" />
      <rect x="7" y="0" width="6" height="20" rx="1.5" fill="currentColor" />
    </svg>
  )
}
