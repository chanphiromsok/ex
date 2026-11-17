import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { money, update, when, type Rec } from '#/lib/api'
import type { Session } from '#/lib/auth'
import { apiKey, listQuery } from '#/lib/queries'
import { formatPhone, phoneHref } from '#/lib/phone'
import { Button, Card, Err, Num, Page, Pill } from '#/components/kit'
import { Combobox, Segmented } from '#/components/form'
import { DataTable, type ColumnDef } from '#/components/data-table'
import { ReasonDialog } from '#/components/reason-dialog'
import { StatusTag } from '#/components/StatusWeave'

const DECISION: Record<string, { label: string; tone: 'turmeric' | 'leaf' | 'neutral' | 'madder' }> = {
  pending: { label: 'Pending', tone: 'turmeric' },
  approved: { label: 'Approved', tone: 'leaf' },
  rejected: { label: 'Rejected', tone: 'neutral' },
  open: { label: 'Open', tone: 'madder' },
  resolved: { label: 'Resolved', tone: 'leaf' },
}
const Decision = ({ status }: { status: string }) => {
  const d = DECISION[status]
  return d ? <Pill tone={d.tone}>{d.label}</Pill> : <Pill>{status}</Pill>
}
const byTime = (a: { original: Rec }, b: { original: Rec }) => String(a.original.inserted_at).localeCompare(String(b.original.inserted_at))

// ---------------------------------------------------------------- Overdue

export function Overdue({ session }: { session: Session }) {
  const [station, setStation] = useState('')
  const isAdmin = session.role === 'admin'
  const stations = useQuery({ ...listQuery('/stations'), enabled: isAdmin })
  const overdue = useQuery(listQuery(`/shipments/overdue${station ? `?destination_station_id=${station}` : ''}`))

  const columns = useMemo<ColumnDef<Rec>[]>(
    () => [
      {
        id: 'invoice',
        accessorFn: (s) => s.invoice_no,
        header: 'Invoice',
        cell: ({ row }) => <Num className="font-semibold">#{row.original.invoice_no}</Num>,
      },
      { id: 'receiver', accessorFn: (s) => s.current_receiver_name, header: 'Receiver' },
      {
        id: 'phone',
        accessorFn: (s) => `${s.current_receiver_phone ?? ''} ${formatPhone(s.current_receiver_phone).replaceAll(' ', '')}`,
        header: 'Phone',
        enableSorting: false,
        cell: ({ row }) => (
          <a
            href={phoneHref(row.original.current_receiver_phone)}
            onClick={(e) => e.stopPropagation()}
            className="tabular text-clay underline-offset-4 hover:underline"
          >
            {formatPhone(row.original.current_receiver_phone)}
          </a>
        ),
      },
      {
        id: 'status',
        accessorFn: (s) => s.status_label_en,
        header: 'Status',
        cell: ({ row }) => <StatusTag status={row.original.status} en={row.original.status_label_en} />,
      },
    ],
    [],
  )

  return (
    <Page title="Overdue Shipments" subtitle="Arrived and waiting longer than the Station's Overdue threshold. Call the Receiver.">
      <Err error={overdue.error} />
      <Card flush>
        <DataTable
          id="overdue-table"
          columns={columns}
          data={overdue.data}
          loading={overdue.isPending}
          empty="Nothing Overdue. Every Arrived Shipment is within its threshold."
          search={{ placeholder: 'Search by Invoice, name or phone' }}
          toolbar={
            isAdmin ? (
              <Combobox
                id="overdue-station"
                aria-label="Destination Station"
                className="w-60"
                value={station || 'all'}
                onChange={(v) => setStation(v === 'all' ? '' : v)}
                searchPlaceholder="Search Stations…"
                options={[{ value: 'all', label: 'All Stations' }, ...(stations.data ?? []).map((s) => ({ value: s.id, label: s.name_en }))]}
              />
            ) : undefined
          }
        />
      </Card>
    </Page>
  )
}

// ---------------------------------------------------------- Cancellations

const CANCEL_FILTER = [
  { value: 'pending', label: 'Pending' },
  { value: 'all', label: 'All' },
]

export function Cancellations({ session }: { session: Session }) {
  const qc = useQueryClient()
  const requests = useQuery(listQuery('/cancellation-requests'))
  const [show, setShow] = useState('pending')
  const [rejecting, setRejecting] = useState<Rec | null>(null)

  const decide = useMutation({
    mutationFn: ({ id, how, why }: { id: string; how: 'approve' | 'reject'; why?: string }) =>
      update(`/cancellation-requests/${id}/${how}`, 'cancellation-request', how === 'reject' ? { decision_reason: why } : {}),
    onSuccess: async (_d, { how }) => {
      toast.success(how === 'approve' ? 'Cancellation approved. Refund recorded.' : 'Cancellation rejected.')
      setRejecting(null)
      await Promise.all([
        qc.invalidateQueries({ queryKey: apiKey('cancellation-requests') }),
        qc.invalidateQueries({ queryKey: apiKey('shipments') }),
      ])
    },
  })
  const canApprove = session.permissions.includes('cancellation.approve')
  const all = requests.data ?? []
  const pending = all.filter((r) => r.status === 'pending').length
  const rows = show === 'pending' ? all.filter((r) => r.status === 'pending') : all

  const columns = useMemo<ColumnDef<Rec>[]>(() => {
    const cols: ColumnDef<Rec>[] = [
      {
        id: 'reason',
        accessorFn: (r) => r.reason,
        header: 'Reason',
        enableSorting: false,
        cell: ({ row }) => <span className="block max-w-xs whitespace-normal">{row.original.reason}</span>,
      },
      {
        id: 'status',
        accessorFn: (r) => r.status,
        header: 'Status',
        cell: ({ row }) => <Decision status={row.original.status} />,
      },
      {
        id: 'fee',
        accessorFn: (r) => Number(r.fee?.amount ?? 0),
        header: 'Fee',
        meta: { align: 'right' },
        cell: ({ row }) => <Num>{money(row.original.fee)}</Num>,
      },
      {
        id: 'refund',
        accessorFn: (r) => Number(r.refund_amount?.amount ?? 0),
        header: 'Refund',
        meta: { align: 'right' },
        cell: ({ row }) => <Num className="font-medium">{money(row.original.refund_amount)}</Num>,
      },
      {
        id: 'requested',
        accessorFn: (r) => r.inserted_at,
        header: 'Requested',
        meta: { align: 'right' },
        sortingFn: byTime,
        cell: ({ row }) => <Num className="text-ink-soft">{when(row.original.inserted_at)}</Num>,
      },
    ]
    if (canApprove)
      cols.push({
        id: 'actions',
        header: () => <span className="sr-only">Actions</span>,
        enableSorting: false,
        meta: { align: 'right' },
        cell: ({ row }) => {
          const r = row.original
          if (r.status !== 'pending') return null
          if (r.requested_by_id === session.userId) return <span className="text-xs text-ink-faint">Your request</span>
          const mine = decide.isPending && decide.variables?.id === r.id
          return (
            <span className="inline-flex gap-1.5">
              <Button
                size="sm"
                busy={mine && decide.variables?.how === 'approve'}
                disabled={decide.isPending}
                onClick={() => decide.mutate({ id: r.id, how: 'approve' })}
              >
                Approve
              </Button>
              <Button size="sm" variant="outline" disabled={decide.isPending} onClick={() => setRejecting(r)}>
                Reject
              </Button>
            </span>
          )
        },
      })
    return cols
  }, [canApprove, session.userId, decide])

  return (
    <Page title="Cancellations" subtitle={requests.isSuccess ? `${pending} waiting for a decision` : undefined}>
      <Err error={requests.error ?? (rejecting ? null : decide.error)} />
      <Card flush>
        <DataTable
          id="cancellations-table"
          columns={columns}
          data={rows}
          loading={requests.isPending}
          empty={show === 'pending' ? 'No Cancellation requests waiting.' : 'No Cancellation requests.'}
          search={{ placeholder: 'Search reasons' }}
          initialSort={[{ id: 'requested', desc: true }]}
          toolbar={<Segmented aria-label="Show" className="w-44" value={show} onChange={setShow} options={CANCEL_FILTER} />}
        />
      </Card>
      <ReasonDialog
        open={!!rejecting}
        onOpenChange={(o) => {
          if (!o) {
            setRejecting(null)
            decide.reset()
          }
        }}
        title="Reject this Cancellation?"
        description={rejecting ? <>The Shipment stays Received and no refund is made. Request reason: “{rejecting.reason}”</> : undefined}
        label="Reason for rejecting"
        fieldId="reject-reason"
        confirm="Reject"
        tone="destructive"
        busy={decide.isPending}
        error={decide.error}
        onConfirm={(why) => rejecting && decide.mutate({ id: rejecting.id, how: 'reject', why })}
      />
    </Page>
  )
}

// -------------------------------------------------------------- Incidents

const KIND: Record<string, string> = { return_to_sender: 'Return to sender', redirect: 'Redirect', lost: 'Lost', damaged: 'Damaged' }
const INCIDENT_FILTER = [
  { value: 'open', label: 'Open' },
  { value: 'all', label: 'All' },
]

export function Incidents({ session }: { session: Session }) {
  const qc = useQueryClient()
  const incidents = useQuery(listQuery('/incidents'))
  const [show, setShow] = useState('open')
  const [resolving, setResolving] = useState<Rec | null>(null)

  const resolve = useMutation({
    mutationFn: ({ id, resolution }: { id: string; resolution: string }) => update(`/incidents/${id}/resolve`, 'incident', { resolution }),
    onSuccess: async () => {
      toast.success('Incident resolved.')
      setResolving(null)
      await qc.invalidateQueries({ queryKey: apiKey('incidents') })
    },
  })
  const can = session.permissions.includes('incident.resolve')
  const all: Rec[] = incidents.data ?? []
  const open = all.filter((i) => i.status === 'open').length
  const rows = show === 'open' ? all.filter((i) => i.status === 'open') : all

  const columns = useMemo<ColumnDef<Rec>[]>(() => {
    const cols: ColumnDef<Rec>[] = [
      {
        id: 'kind',
        accessorFn: (i) => KIND[i.kind] ?? i.kind,
        header: 'Kind',
        cell: ({ getValue }) => <span className="font-medium">{getValue<string>()}</span>,
      },
      {
        id: 'note',
        accessorFn: (i) => i.note,
        header: 'Note',
        enableSorting: false,
        cell: ({ row }) => <span className="block max-w-xs whitespace-normal text-ink-soft">{row.original.note}</span>,
      },
      {
        id: 'status',
        accessorFn: (i) => i.status,
        header: 'Status',
        cell: ({ row }) => <Decision status={row.original.status} />,
      },
      {
        id: 'resolution',
        accessorFn: (i) => i.resolution ?? '',
        header: 'Resolution',
        enableSorting: false,
        cell: ({ row }) => <span className="block max-w-xs whitespace-normal text-ink-soft">{row.original.resolution ?? ''}</span>,
      },
      {
        id: 'reported',
        accessorFn: (i) => i.inserted_at,
        header: 'Reported',
        meta: { align: 'right' },
        sortingFn: byTime,
        cell: ({ row }) => <Num className="text-ink-soft">{when(row.original.inserted_at)}</Num>,
      },
    ]
    if (can)
      cols.push({
        id: 'actions',
        header: () => <span className="sr-only">Actions</span>,
        enableSorting: false,
        meta: { align: 'right' },
        cell: ({ row }) =>
          row.original.status === 'open' ? (
            <Button size="sm" variant="outline" onClick={() => setResolving(row.original)}>
              Resolve
            </Button>
          ) : null,
      })
    return cols
  }, [can])

  return (
    <Page title="Incidents" subtitle={incidents.isSuccess ? `${open} open` : undefined}>
      <Err error={incidents.error} />
      <Card flush>
        <DataTable
          id="incidents-table"
          columns={columns}
          data={rows}
          loading={incidents.isPending}
          empty={show === 'open' ? 'No open Incidents.' : 'No Incidents reported.'}
          search={{ placeholder: 'Search kind, note or resolution' }}
          initialSort={[{ id: 'reported', desc: true }]}
          toolbar={<Segmented aria-label="Show" className="w-44" value={show} onChange={setShow} options={INCIDENT_FILTER} />}
        />
      </Card>
      <ReasonDialog
        open={!!resolving}
        onOpenChange={(o) => {
          if (!o) {
            setResolving(null)
            resolve.reset()
          }
        }}
        title={resolving ? `Resolve ${KIND[resolving.kind] ?? resolving.kind} Incident` : 'Resolve Incident'}
        description={resolving?.note ? <>Reported: “{resolving.note}”</> : undefined}
        label="Resolution"
        fieldId="resolution"
        confirm="Resolve"
        busy={resolve.isPending}
        error={resolve.error}
        onConfirm={(resolution) => resolving && resolve.mutate({ id: resolving.id, resolution })}
      />
    </Page>
  )
}
