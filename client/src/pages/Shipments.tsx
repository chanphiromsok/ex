import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'
import { ArrowRight, PackageCheck, Truck, Warehouse } from 'lucide-react'
import { create, money, update, when, type Rec } from '#/lib/api'
import type { Session } from '#/lib/auth'
import { apiKey, listQuery, recordQuery } from '#/lib/queries'
import { formatPhone, phoneSchema } from '#/lib/phone'
import { Button, Card, Err, Num, Page, Pill } from '#/components/kit'
import { Choice, FormField } from '#/components/form'
import { DataTable, type ColumnDef } from '#/components/data-table'
import { StatusTag, StatusWeave } from '#/components/StatusWeave'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'

const stationName = (stations: Rec[] | undefined, id?: string) => stations?.find((s) => s.id === id)?.name_en ?? '—'

export function Shipments({ session }: { session: Session }) {
  const shipments = useQuery(listQuery('/shipments'))
  const stations = useQuery(listQuery('/stations'))
  const [selected, setSelected] = useState<string | null>(null)

  const columns = useMemo<ColumnDef<Rec, any>[]>(
    () => [
      {
        id: 'invoice',
        header: 'Invoice',
        accessorFn: (s) => `#${s.invoice_no}`,
        sortingFn: (a, b) => Number(a.original.invoice_no) - Number(b.original.invoice_no),
        cell: ({ row }) => <span className="tabular font-semibold text-clay">#{row.original.invoice_no}</span>,
      },
      {
        id: 'sender',
        header: 'Sender',
        accessorFn: (s) => `${s.sender_name ?? ''} ${s.sender_phone ?? ''} ${formatPhone(s.sender_phone).replaceAll(' ', '')}`,
        cell: ({ row }) => <Person name={row.original.sender_name} phone={row.original.sender_phone} />,
      },
      {
        id: 'receiver',
        header: 'Receiver',
        accessorFn: (s) =>
          `${s.current_receiver_name ?? ''} ${s.current_receiver_phone ?? ''} ${s.receiver_phone ?? ''} ${formatPhone(s.current_receiver_phone).replaceAll(' ', '')}`,
        cell: ({ row }) => <Person name={row.original.current_receiver_name} phone={row.original.current_receiver_phone} />,
      },
      {
        id: 'to',
        header: 'To',
        accessorFn: (s) => stationName(stations.data, s.destination_station_id),
        cell: ({ getValue }) => <span className="text-ink-soft">{getValue()}</span>,
      },
      {
        id: 'status',
        header: 'Status',
        accessorFn: (s) => s.status_label_en ?? s.status,
        cell: ({ row }) => <StatusTag status={row.original.status} en={row.original.status_label_en} km={row.original.status_label_km} />,
      },
      {
        id: 'total',
        header: 'Shipment Total',
        accessorFn: (s) => Number(s.shipment_total?.amount ?? 0),
        meta: { align: 'right' },
        enableGlobalFilter: false,
        cell: ({ row }) => <Num className="font-medium">{money(row.original.shipment_total)}</Num>,
      },
      {
        id: 'received',
        header: 'Received',
        accessorFn: (s) => s.inserted_at,
        meta: { align: 'right' },
        enableGlobalFilter: false,
        cell: ({ row }) => <Num className="text-ink-soft">{when(row.original.inserted_at)}</Num>,
      },
    ],
    [stations.data],
  )

  if (selected) return <Detail id={selected} session={session} onBack={() => setSelected(null)} />

  const rows = shipments.data ?? []
  return (
    <Page title="Shipments" subtitle={shipments.isSuccess ? `${rows.length.toLocaleString('en-US')} on record` : undefined}>
      <Err error={shipments.error} />
      <Card flush>
        <DataTable
          id="shipments-table"
          columns={columns}
          data={rows}
          loading={shipments.isPending}
          empty="No Shipments yet."
          search={{ id: 'search', placeholder: 'Invoice, name or phone number', label: 'Find a Shipment', autoFocus: true }}
          initialSort={[{ id: 'received', desc: true }]}
          onRowClick={(s) => setSelected(s.id)}
          rowLabel={(s) => `Open Invoice #${s.invoice_no}`}
        />
      </Card>
    </Page>
  )
}

function Person({ name, phone }: { name?: string; phone?: string }) {
  return (
    <span className="block max-w-56 min-w-0">
      <span className="block truncate text-ink">{name}</span>
      {phone && <span className="tabular block text-xs text-ink-faint">{formatPhone(phone)}</span>}
    </span>
  )
}

const INCIDENT_KINDS = [
  { value: 'damaged', label: 'Damaged' },
  { value: 'lost', label: 'Lost' },
  { value: 'redirect', label: 'Redirect' },
  { value: 'return_to_sender', label: 'Return to sender' },
]
const METHOD: Record<string, string> = { cash: 'Cash', bank_transfer: 'Bank transfer', qr: 'QR' }

const phone = phoneSchema
const required = (msg: string) => z.string().trim().min(1, msg)

const collectSchema = z.object({ receiver_phone: phone })
const noteSchema = z.object({ body: required('Write a Note first.') })
const correctSchema = z.object({ name: required('Enter the new Receiver name.'), phone, reason: required('Say why it changed.') })
const incidentSchema = z.object({ kind: z.enum(['damaged', 'lost', 'redirect', 'return_to_sender']), note: z.string().trim() })
const cancelSchema = z.object({ reason: required('A reason is required to cancel.') })

function Detail({ id, session, onBack }: { id: string; session: Session; onBack: () => void }) {
  const qc = useQueryClient()
  const shipment = useQuery(recordQuery(`/shipments/${id}?include=parcels,sale_items,payments,status_events,notes,receiver_corrections`))
  const saleItems = useQuery(listQuery('/sale-items'))
  const sizeClasses = useQuery(listQuery('/size-classes'))
  const stations = useQuery(listQuery('/stations'))
  const has = (p: string) => session.permissions.includes(p)

  const collectForm = useForm({ resolver: zodResolver(collectSchema), defaultValues: { receiver_phone: '' } })
  const noteForm = useForm({ resolver: zodResolver(noteSchema), defaultValues: { body: '' } })
  const correctForm = useForm({ resolver: zodResolver(correctSchema), defaultValues: { name: '', phone: '', reason: '' } })
  const incidentForm = useForm({ resolver: zodResolver(incidentSchema), defaultValues: { kind: 'damaged' as const, note: '' } })
  const cancelForm = useForm({ resolver: zodResolver(cancelSchema), defaultValues: { reason: '' } })

  // Every action changes the Shipment; refresh it and the lists it appears in.
  const action = <V,>(fn: (v: V) => Promise<unknown>, done: string, after?: () => void, also?: string) => ({
    mutationFn: fn,
    onSuccess: async () => {
      after?.()
      toast.success(done)
      await Promise.all([
        qc.invalidateQueries({ queryKey: apiKey('shipments') }),
        also ? qc.invalidateQueries({ queryKey: apiKey(also) }) : null,
      ])
    },
  })

  const inTransit = useMutation(action(() => update(`/shipments/${id}/in-transit`, 'shipment', {}), 'Marked in transit'))
  const arrived = useMutation(action(() => update(`/shipments/${id}/arrived`, 'shipment', {}), 'Marked arrived'))
  const collect = useMutation(
    action((v: z.infer<typeof collectSchema>) => update(`/shipments/${id}/collect`, 'shipment', v), 'Handed over to the Receiver', () => collectForm.reset()),
  )
  const note = useMutation(
    action((v: z.infer<typeof noteSchema>) => create('/shipment-notes', 'shipment-note', { shipment_id: id, ...v }), 'Note added', () => noteForm.reset()),
  )
  const correct = useMutation(
    action(
      (v: z.infer<typeof correctSchema>) => create('/receiver-corrections', 'receiver-correction', { shipment_id: id, ...v }),
      'Receiver corrected',
      () => correctForm.reset(),
    ),
  )
  const incident = useMutation(
    action(
      (v: z.infer<typeof incidentSchema>) => create('/incidents', 'incident', { shipment_id: id, ...v }),
      'Incident reported',
      () => incidentForm.reset(),
      'incidents',
    ),
  )
  const cancel = useMutation(
    action(
      (v: z.infer<typeof cancelSchema>) => create('/cancellation-requests', 'cancellation-request', { shipment_id: id, ...v }),
      'Cancellation requested',
      () => cancelForm.reset(),
      'cancellation-requests',
    ),
  )

  const s = shipment.data
  const sizeName = (sid: string) => sizeClasses.data?.find((c) => c.id === sid)?.name_en ?? 'By size'
  const itemName = (sid: string) => saleItems.data?.find((i) => i.id === sid)?.name_en ?? 'Sale Item'

  const parcelCols = useMemo<ColumnDef<Rec, any>[]>(
    () => [
      { id: 'n', header: 'Parcel', accessorFn: (_p, i) => i + 1, cell: ({ getValue }) => <Num>{getValue()}</Num> },
      {
        id: 'measure',
        header: 'Measure',
        accessorFn: (p) => (p.measurement_type === 'kg' ? `${p.weight_kg} kg` : sizeName(p.size_class_id)),
        cell: ({ getValue }) => <Num>{getValue()}</Num>,
      },
      {
        id: 'charge',
        header: 'Charge',
        meta: { align: 'right' },
        accessorFn: (p) => Number(p.chargeable_amount?.amount ?? 0),
        cell: ({ row }) => <Num>{money(row.original.chargeable_amount)}</Num>,
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [sizeClasses.data],
  )
  const itemCols = useMemo<ColumnDef<Rec, any>[]>(
    () => [
      { id: 'item', header: 'Item', accessorFn: (p) => itemName(p.sale_item_id) },
      { id: 'qty', header: 'Qty', meta: { align: 'right' }, accessorFn: (p) => p.quantity, cell: ({ getValue }) => <Num>{getValue()}</Num> },
      {
        id: 'unit',
        header: 'Unit price',
        meta: { align: 'right' },
        accessorFn: (p) => Number(p.unit_price?.amount ?? 0),
        cell: ({ row }) => <Num>{money(row.original.unit_price)}</Num>,
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [saleItems.data],
  )
  const paymentCols = useMemo<ColumnDef<Rec, any>[]>(
    () => [
      {
        id: 'kind',
        header: 'Kind',
        accessorFn: (p) => p.kind,
        cell: ({ getValue }) => (getValue() === 'refund' ? <Pill tone="madder">Refund</Pill> : <Pill>Payment</Pill>),
      },
      { id: 'method', header: 'Method', accessorFn: (p) => METHOD[p.method] ?? p.method },
      {
        id: 'amount',
        header: 'Amount',
        meta: { align: 'right' },
        accessorFn: (p) => Number(p.amount?.amount ?? 0),
        cell: ({ row }) => {
          const refund = row.original.kind === 'refund'
          return (
            <Num className={refund ? 'text-madder-deep' : ''}>
              {refund ? '− ' : ''}
              {money(row.original.amount)}
            </Num>
          )
        },
      },
      {
        id: 'when',
        header: 'When',
        meta: { align: 'right' },
        accessorFn: (p) => p.inserted_at,
        cell: ({ getValue }) => <Num className="text-ink-soft">{when(getValue())}</Num>,
      },
    ],
    [],
  )
  const historyCols = useMemo<ColumnDef<Rec, any>[]>(
    () => [
      { id: 'seq', header: '#', accessorFn: (e) => e.seq, meta: { className: 'w-12' }, cell: ({ getValue }) => <Num className="text-ink-faint">{getValue()}</Num> },
      {
        id: 'status',
        header: 'Status',
        accessorFn: (e) => e.status_label_en ?? e.status,
        cell: ({ row }) => (
          <span>
            <StatusTag status={row.original.status} en={row.original.status_label_en} />
            {row.original.reason && <span className="mt-0.5 block text-xs text-ink-soft">{row.original.reason}</span>}
          </span>
        ),
      },
      { id: 'station', header: 'Station', accessorFn: (e) => stationName(stations.data, e.station_id) },
      {
        id: 'when',
        header: 'When',
        meta: { align: 'right' },
        accessorFn: (e) => e.inserted_at,
        cell: ({ getValue }) => <Num className="text-ink-soft">{when(getValue())}</Num>,
      },
    ],
    [stations.data],
  )

  if (!s)
    return (
      <Page title="Shipment" onBack={onBack} backLabel="All Shipments">
        {shipment.isPending ? (
          <Card>
            <div className="h-24 animate-pulse rounded bg-sunk" />
          </Card>
        ) : (
          <Err error={shipment.error} />
        )}
      </Page>
    )

  const origin = s.origin_station_id === session.stationId
  const dest = s.destination_station_id === session.stationId
  const events = [...(s.status_events ?? [])].sort((a: Rec, b: Rec) => a.seq - b.seq)
  const corrected = s.current_receiver_name !== s.receiver_name || s.current_receiver_phone !== s.receiver_phone

  const canInTransit = has('shipment.mark_in_transit') && s.status === 'received' && origin
  const canArrive = has('shipment.mark_arrived') && s.status === 'in_transit' && dest
  const canCollect = has('shipment.collect') && s.status === 'arrived' && dest
  const nextStep = canInTransit || canArrive || canCollect

  return (
    <Page
      onBack={onBack}
      backLabel="All Shipments"
      title={<span className="tabular">Invoice #{s.invoice_no}</span>}
      subtitle={
        <span className="inline-flex items-center gap-1.5">
          {stationName(stations.data, s.origin_station_id)}
          <ArrowRight aria-hidden className="size-3.5 text-ink-faint" />
          {stationName(stations.data, s.destination_station_id)}
        </span>
      }
      action={
        <div className="text-right">
          <p className="text-xs text-ink-soft">Shipment Total</p>
          <Num className="text-[22px] font-semibold tracking-[-0.01em]">{money(s.shipment_total)}</Num>
        </div>
      }
    >
      <Card>
        <StatusWeave status={s.status} events={events} />
      </Card>

      <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_340px]">
        <div className="min-w-0 space-y-5">
          <Card flush>
            <dl className="grid divide-thread sm:grid-cols-2 sm:divide-x">
              <div className="px-5 py-4">
                <dt className="text-xs text-ink-soft">Sender</dt>
                <dd className="mt-1 font-medium">{s.sender_name}</dd>
                <dd className="tabular text-[13px] text-ink-soft">{formatPhone(s.sender_phone)}</dd>
              </div>
              <div className="border-t border-thread px-5 py-4 sm:border-t-0">
                <dt className="flex items-center gap-2 text-xs text-ink-soft">
                  Receiver {corrected && <Pill tone="turmeric">Corrected</Pill>}
                </dt>
                <dd className="mt-1 font-medium">{s.current_receiver_name}</dd>
                <dd className="tabular text-[13px] text-ink-soft">{formatPhone(s.current_receiver_phone)}</dd>
                {corrected && (
                  <dd className="mt-1 text-xs text-ink-faint">
                    Was {s.receiver_name} · <span className="tabular">{formatPhone(s.receiver_phone)}</span>
                  </dd>
                )}
              </div>
            </dl>
          </Card>

          <Card title="Parcels" flush>
            <DataTable id="parcels-table" columns={parcelCols} data={s.parcels ?? []} empty="No Parcels." />
          </Card>

          {(s.sale_items ?? []).length > 0 && (
            <Card title="Sale Items" flush>
              <DataTable id="sale-items-table" columns={itemCols} data={s.sale_items ?? []} />
            </Card>
          )}

          <Card title="Payments" flush>
            <DataTable id="payments-table" columns={paymentCols} data={s.payments ?? []} empty="No Payments." />
          </Card>

          <Card title="History" flush>
            <DataTable id="history-table" columns={historyCols} data={events} initialSort={[{ id: 'seq', desc: false }]} />
          </Card>
        </div>

        <aside className="no-print space-y-5">
          {nextStep && (
            <Card title="Next step" className="border-clay/30">
              {canInTransit && (
                <Button
                  id="in-transit"
                  icon={<Truck aria-hidden className="size-4" />}
                  busy={inTransit.isPending}
                  onClick={() => inTransit.mutate(undefined)}
                  className="w-full"
                >
                  Mark in transit
                </Button>
              )}
              {canArrive && (
                <Button
                  id="arrived"
                  icon={<Warehouse aria-hidden className="size-4" />}
                  busy={arrived.isPending}
                  onClick={() => arrived.mutate(undefined)}
                  className="w-full"
                >
                  Mark arrived
                </Button>
              )}
              {canCollect && (
                <form className="space-y-3" noValidate onSubmit={collectForm.handleSubmit((v) => collect.mutate(v))}>
                  <FormField
                    control={collectForm.control}
                    name="receiver_phone"
                    id="collect-phone"
                    label="Receiver phone"
                    description="Must match the Receiver's phone on the Invoice."
                  >
                    {(f) => <Input {...f} inputMode="tel" autoComplete="off" className="tabular" />}
                  </FormField>
                  <Button id="collect" type="submit" icon={<PackageCheck aria-hidden className="size-4" />} busy={collect.isPending} className="w-full">
                    Hand over
                  </Button>
                </form>
              )}
              <Err error={inTransit.error ?? arrived.error ?? collect.error} />
            </Card>
          )}

          {has('shipment.add_note') && (
            <Card title="Notes">
              {(s.notes ?? []).length > 0 ? (
                <ul className="space-y-3">
                  {(s.notes ?? []).map((n: Rec) => (
                    <li key={n.id} className="border-l-2 border-thread pl-3 text-sm">
                      <p className="text-ink">{n.body}</p>
                      <p className="tabular text-xs text-ink-faint">{when(n.inserted_at)}</p>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-ink-soft">No Notes yet.</p>
              )}
              <form className="space-y-2" noValidate onSubmit={noteForm.handleSubmit((v) => note.mutate(v))}>
                <FormField control={noteForm.control} name="body" label={<span className="sr-only">Note</span>}>
                  {(f) => <Textarea {...f} rows={2} placeholder="Add a Note" className="min-h-16 resize-none" />}
                </FormField>
                <Button type="submit" variant="outline" size="sm" busy={note.isPending}>
                  Add note
                </Button>
              </form>
              <Err error={note.error} />
            </Card>
          )}

          {has('receiver.correct') && (
            <Card title="Correct Receiver">
              <form className="space-y-3" noValidate onSubmit={correctForm.handleSubmit((v) => correct.mutate(v))}>
                <FormField control={correctForm.control} name="name" label="Name">
                  {(f) => <Input {...f} autoComplete="off" />}
                </FormField>
                <FormField control={correctForm.control} name="phone" label="Phone">
                  {(f) => <Input {...f} inputMode="tel" autoComplete="off" className="tabular" />}
                </FormField>
                <FormField control={correctForm.control} name="reason" label="Reason">
                  {(f) => <Input {...f} autoComplete="off" />}
                </FormField>
                <Button type="submit" variant="outline" busy={correct.isPending}>
                  Save correction
                </Button>
              </form>
              <Err error={correct.error} />
            </Card>
          )}

          {has('incident.report') && (
            <Card title="Report Incident">
              <form className="space-y-3" noValidate onSubmit={incidentForm.handleSubmit((v) => incident.mutate(v))}>
                <FormField control={incidentForm.control} name="kind" label="Kind">
                  {(f) => <Choice id={f.id} value={f.value} onChange={f.onChange} options={INCIDENT_KINDS} invalid={f['aria-invalid']} />}
                </FormField>
                <FormField control={incidentForm.control} name="note" label="Note" description="Optional. What happened, and where.">
                  {(f) => <Textarea {...f} rows={2} className="min-h-16 resize-none" />}
                </FormField>
                <Button type="submit" variant="outline" busy={incident.isPending}>
                  Report
                </Button>
              </form>
              <Err error={incident.error} />
            </Card>
          )}

          {has('cancellation.request') && s.status === 'received' && (
            <Card title="Cancel Shipment" description="Only a Received Shipment can be cancelled. A fee may be kept from the refund.">
              <form className="space-y-3" noValidate onSubmit={cancelForm.handleSubmit((v) => cancel.mutate(v))}>
                <FormField control={cancelForm.control} name="reason" id="cancel-reason" label="Reason">
                  {(f) => <Input {...f} autoComplete="off" />}
                </FormField>
                <Button id="cancel" type="submit" variant="destructive" busy={cancel.isPending}>
                  Request cancellation
                </Button>
              </form>
              <Err error={cancel.error} />
            </Card>
          )}
        </aside>
      </div>
    </Page>
  )
}
