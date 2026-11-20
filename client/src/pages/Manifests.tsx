import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from '@tanstack/react-router'
import { toast } from 'sonner'
import { Bus, PackageCheck, Plus, ScanLine } from 'lucide-react'
import { create, update, when, type Rec } from '#/lib/api'
import type { Session } from '#/lib/auth'
import { getManifestsByIdOptions, getManifestsDeparturesOptions, getManifestsInfiniteOptions, getStationsOptions } from '#/api/@tanstack/react-query.gen'
import { usePaged } from '#/lib/paged'
import { asRow, asRows, resource } from '#/lib/queries'
import { Button, Card, Err, Page, Pill } from '#/components/kit'
import { Choice } from '#/components/form'
import { DataTable, type ColumnDef } from '#/components/data-table'
import { Input } from '@/components/ui/input'

const STATUS: Record<string, { label: string; tone: 'neutral' | 'clay' | 'green' }> = {
  open: { label: 'Loading', tone: 'neutral' },
  departed: { label: 'On the road', tone: 'clay' },
  arrived: { label: 'Arrived', tone: 'green' },
}
const stationName = (stations: Rec[] | undefined, id?: string) => stations?.find((s) => s.id === id)?.name_en ?? '—'
const clock = (iso?: string) => (iso ? when(iso) : '—')
const today = () => new Date().toISOString().slice(0, 10)

function StatusPill({ status }: { status: string }) {
  const s = STATUS[status] ?? { label: status, tone: 'neutral' as const }
  return <Pill tone={s.tone as any}>{s.label}</Pill>
}

export function Manifests({ session }: { session: Session }) {
  const navigate = useNavigate()
  const manifests = usePaged(getManifestsInfiniteOptions())
  const stations = useQuery({ ...getStationsOptions(), select: asRows })

  const columns = useMemo<ColumnDef<Rec, any>[]>(
    () => [
      { id: 'departs', header: 'Departs', accessorFn: (m) => m.departs_at, cell: ({ row }) => <span className="tabular font-medium">{clock(row.original.departs_at)}</span> },
      { id: 'bus', header: 'Bus', accessorFn: (m) => m.bus_label ?? '', cell: ({ getValue }) => <span className="text-ink-soft">{getValue() || '—'}</span> },
      {
        id: 'route',
        header: 'Route',
        accessorFn: (m) => `${stationName(stations.data, m.origin_station_id)} → ${stationName(stations.data, m.destination_station_id)}`,
      },
      {
        id: 'loaded',
        header: 'Shipments',
        enableGlobalFilter: false,
        accessorFn: (m) => Number(m.shipment_count ?? 0),
        meta: { align: 'right' },
        cell: ({ row }) => (
          <span className="tabular">
            {row.original.shipment_count ?? 0}
            {row.original.status === 'departed' && Number(row.original.remaining_count) > 0 && (
              <span className="ml-1 text-xs text-ink-faint">({row.original.remaining_count} to unload)</span>
            )}
          </span>
        ),
      },
      { id: 'status', header: 'Status', accessorFn: (m) => m.status, cell: ({ row }) => <StatusPill status={row.original.status} /> },
    ],
    [stations.data],
  )

  const canOpen = session.permissions.includes('shipment.mark_in_transit')
  return (
    <Page
      title="Manifests"
      subtitle="One list per bus trip: what is loaded at the origin and unloaded at the destination."
      action={canOpen ? <Button id="open-manifest" icon={<Plus className="size-4" />} onClick={() => navigate({ to: '/manifests/new' })}>Open a Manifest</Button> : undefined}
    >
      <Err error={manifests.error} />
      <Card flush>
        <DataTable
          id="manifests-table"
          columns={columns}
          data={manifests.rows}
          loading={manifests.isPending}
          more={manifests.more}
          empty="No Manifests yet."
          search={{ id: 'manifest-search', placeholder: 'Bus or Station', label: 'Find a Manifest' }}
          initialSort={[{ id: 'departs', desc: true }]}
          onRowClick={(m) => navigate({ to: '/manifests/$id', params: { id: m.id } })}
          rowLabel={(m) => `Open the ${clock(m.departs_at)} Manifest`}
        />
      </Card>
    </Page>
  )
}

export function OpenManifest({ session }: { session: Session }) {
  const navigate = useNavigate()
  const stations = useQuery({ ...getStationsOptions(), select: asRows }).data ?? []
  const onBack = () => navigate({ to: '/manifests' })
  const onOpened = (id: string) => navigate({ to: '/manifests/$id', params: { id }, replace: true })
  const [destination, setDestination] = useState('')
  const [date, setDate] = useState(today())
  const options = stations.filter((s) => s.id !== session.stationId && s.active !== false).map((s) => ({ value: s.id, label: s.name_en, hint: s.name_km }))
  const departures = useQuery({
    ...getManifestsDeparturesOptions({ query: { destination_station_id: destination, date } }),
    enabled: !!destination && !!date,
    select: (j: any): Rec[] => (Array.isArray(j) ? j : (j?.data ?? [])),
  })
  const qc = useQueryClient()
  const open = useMutation({
    mutationFn: (trip_id: string) => create('/manifests', 'manifest', { external_trip_id: trip_id, destination_station_id: destination }),
    onSuccess: (m) => {
      qc.invalidateQueries({ ...resource('manifests') })
      toast.success('Manifest opened')
      onOpened(m.id)
    },
    onError: (e: Error) => toast.error(e.message),
  })

  return (
    <Page title="Open a Manifest" subtitle="Choose where the bus is going, then the departure." onBack={onBack} backLabel="Manifests">
      <Card>
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="grid gap-1.5 text-sm font-medium">
            Destination Station
            <Choice id="manifest-destination" value={destination} onChange={setDestination} options={options} placeholder="Choose a Station" />
          </label>
          <label className="grid gap-1.5 text-sm font-medium">
            Date
            <Input id="manifest-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
        </div>
      </Card>
      <Err error={departures.error ?? open.error} />
      {destination && (
        <Card title="Departures" flush>
          {departures.isPending ? (
            <p className="p-4 text-sm text-ink-soft">Loading the schedule…</p>
          ) : (departures.data ?? []).length === 0 ? (
            <p className="p-4 text-sm text-ink-soft">No departures that day.</p>
          ) : (
            <ul className="divide-y divide-line">
              {(departures.data ?? []).map((d) => (
                <li key={d.trip_id} className="flex items-center justify-between gap-3 px-4 py-3">
                  <div>
                    <div className="tabular font-medium">{clock(d.departs_at)}</div>
                    <div className="text-xs text-ink-faint">{d.bus_label ?? 'Bus not set'}</div>
                  </div>
                  {d.departed ? (
                    <Pill>Already left</Pill>
                  ) : (
                    <Button variant="secondary" busy={open.isPending && open.variables === d.trip_id} onClick={() => open.mutate(d.trip_id)}>
                      Open
                    </Button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}
    </Page>
  )
}

export function ManifestDetail({ id, session }: { id: string; session: Session }) {
  const navigate = useNavigate()
  const stations = useQuery({ ...getStationsOptions(), select: asRows }).data
  const onBack = () => navigate({ to: '/manifests' })
  const qc = useQueryClient()
  const manifest = useQuery({ ...getManifestsByIdOptions({ path: { id }, query: { include: 'shipments' } }), select: asRow })
  const [invoice, setInvoice] = useState('')
  const m = manifest.data
  const refresh = () => qc.invalidateQueries({ ...resource('manifests') })
  const done = { onSuccess: refresh, onError: (e: Error) => toast.error(e.message) }
  const clearErrors = () => { scan.reset(); depart.reset(); arrive.reset() }

  const scan = useMutation({
    mutationFn: (no: number) => update(`/manifests/${id}/scan`, 'manifest', { invoice_no: no }),
    onSuccess: (_r, no) => {
      clearErrors()
      toast.success(`Invoice #${no} scanned`)
      setInvoice('')
      refresh()
      qc.invalidateQueries({ ...resource('shipments') })
    },
    onError: (e: Error) => toast.error(e.message),
  })
  const depart = useMutation({ mutationFn: () => update(`/manifests/${id}/depart`, 'manifest', {}), ...done, onSuccess: () => { clearErrors(); toast.success('Bus marked as departed'); refresh(); qc.invalidateQueries({ ...resource('shipments') }) } })
  const arrive = useMutation({ mutationFn: () => update(`/manifests/${id}/arrive`, 'manifest', {}), ...done, onSuccess: () => { clearErrors(); toast.success('Manifest closed'); refresh(); qc.invalidateQueries({ ...resource('shipments') }) } })

  if (!m) return <Page title="Manifest" onBack={onBack} backLabel="Manifests"><Err error={manifest.error} /></Page>

  const atOrigin = m.origin_station_id === session.stationId
  const atDestination = m.destination_station_id === session.stationId
  const shipments: Rec[] = m.shipments ?? []
  const canScan = (m.status === 'open' && atOrigin) || (m.status === 'departed' && atDestination)
  const verb = m.status === 'open' ? 'Load' : 'Unload'

  return (
    <Page
      title={`${clock(m.departs_at)} · ${stationName(stations, m.origin_station_id)} → ${stationName(stations, m.destination_station_id)}`}
      subtitle={m.bus_label ?? undefined}
      onBack={onBack}
      backLabel="Manifests"
      action={<StatusPill status={m.status} />}
    >
      <Err error={manifest.error ?? scan.error ?? depart.error ?? arrive.error} />
      <div className="flex flex-wrap items-end gap-3">
        {canScan && (
          <form
            id="scan-form"
            className="flex items-end gap-2"
            onSubmit={(e) => {
              e.preventDefault()
              const n = Number(invoice.replace('#', '').trim())
              if (!Number.isInteger(n) || n <= 0) return toast.error('Enter the Invoice Number.')
              scan.mutate(n)
            }}
          >
            <label className="grid gap-1.5 text-sm font-medium">
              {verb} by Invoice Number
              <Input id="scan-invoice" autoFocus inputMode="numeric" autoComplete="off" placeholder="Scan or type #" value={invoice} onChange={(e) => setInvoice(e.target.value)} />
            </label>
            <Button type="submit" icon={<ScanLine className="size-4" />} busy={scan.isPending}>{verb}</Button>
          </form>
        )}
        {m.status === 'open' && atOrigin && (
          <Button id="depart-manifest" icon={<Bus className="size-4" />} variant="secondary" busy={depart.isPending} disabled={shipments.length === 0} onClick={() => depart.mutate()}>
            Bus has left
          </Button>
        )}
        {m.status === 'departed' && atDestination && (
          <Button id="arrive-manifest" icon={<PackageCheck className="size-4" />} variant="secondary" busy={arrive.isPending} onClick={() => arrive.mutate()}>
            Close Manifest
          </Button>
        )}
      </div>
      <Card
        title="Shipments"
        description={`${shipments.length} loaded${m.status !== 'open' && (m.remaining_count ?? 0) > 0 ? `, ${m.remaining_count} ${m.status === 'arrived' ? 'never unloaded' : 'still to unload'}` : ''}`}
        flush
      >
        {shipments.length === 0 ? (
          <p className="p-4 text-sm text-ink-soft">Nothing loaded yet. Scan an Invoice Number to add a Shipment.</p>
        ) : (
          <ul className="divide-y divide-line">
            {shipments.map((s) => (
              <li key={s.id} className="flex items-center justify-between gap-3 px-4 py-2.5 text-sm">
                <span className="tabular font-semibold text-clay">#{s.invoice_no}</span>
                <span className="flex-1 truncate text-ink-soft">{s.current_receiver_name || s.receiver_phone || ''}</span>
                <Pill tone={s.status === 'in_transit' ? 'clay' : 'neutral'}>{s.status_label_en ?? s.status}</Pill>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </Page>
  )
}
