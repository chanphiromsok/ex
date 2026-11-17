import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useFieldArray, useForm, useWatch } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'
import { Minus, Plus, Printer, Trash2 } from 'lucide-react'
import { create, money } from '#/lib/api'
import { apiKey, listQuery } from '#/lib/queries'
import { phoneSchema } from '#/lib/phone'
import { Bilingual, Button, Card, Err, Num, Page } from '#/components/kit'
import { Combobox, FormField, Segmented } from '#/components/form'
import { Input } from '@/components/ui/input'

const METHODS = [
  { value: 'cash', label: 'Cash' },
  { value: 'bank_transfer', label: 'Bank transfer' },
  { value: 'qr', label: 'QR' },
]
const MODES = [
  { value: 'kg', label: 'Weight' },
  { value: 'size', label: 'Size Class' },
]

const phone = phoneSchema

const parcel = z
  .object({ mode: z.enum(['kg', 'size']), weight: z.string().trim(), size: z.string() })
  .superRefine((p, ctx) => {
    if (p.mode === 'kg' && !(Number(p.weight) > 0))
      ctx.addIssue({ code: 'custom', path: ['weight'], message: 'Enter a weight above 0.' })
    if (p.mode === 'size' && !p.size) ctx.addIssue({ code: 'custom', path: ['size'], message: 'Choose a Size Class.' })
  })

const schema = z.object({
  sender_name: z.string().trim().min(1, 'Enter the Sender name.'),
  sender_phone: phone,
  receiver_name: z.string().trim().min(1, 'Enter the Receiver name.'),
  receiver_phone: phone,
  destination: z.string().min(1, 'Choose a Destination Station.'),
  declared: z.string().trim().regex(/^\d*$/, 'Whole riel only, no commas.'),
  method: z.enum(['cash', 'bank_transfer', 'qr']),
  parcels: z.array(parcel).min(1, 'Add at least one Parcel.'),
  items: z.record(z.string(), z.number().int().min(0)),
})
type Values = z.infer<typeof schema>
type ParcelValues = Values['parcels'][number]

const blankParcel = (): ParcelValues => ({ mode: 'kg', weight: '', size: '' })
const blank = (method: Values['method'] = 'cash', destination = ''): Values => ({
  sender_name: '',
  sender_phone: '',
  receiver_name: '',
  receiver_phone: '',
  destination,
  declared: '',
  method,
  parcels: [blankParcel()],
  items: {},
})

const riel = (n: number) => money({ amount: String(n), currency: 'KHR' })

export function NewShipment({ stationId }: { stationId: string | null }) {
  const qc = useQueryClient()
  const stationsQ = useQuery(listQuery('/stations'))
  const sizesQ = useQuery(listQuery('/size-classes'))
  const itemsQ = useQuery(listQuery('/sale-items'))
  const pricingQ = useQuery(listQuery('/pricing/current'))

  const stations = (stationsQ.data ?? []).filter((s) => s.active && s.id !== stationId)
  const sizes = (sizesQ.data ?? []).filter((s) => s.active)
  const items = (itemsQ.data ?? []).filter((s) => s.active)
  const perKg = pricingQ.data?.[0] ? Number(pricingQ.data[0].price_per_kg.amount) : null
  const loadError = stationsQ.error ?? sizesQ.error ?? itemsQ.error ?? pricingQ.error

  // One key per attempt, so a retried submit can't create the Shipment twice.
  const [key, setKey] = useState(() => crypto.randomUUID())
  const form = useForm<Values>({ resolver: zodResolver(schema), defaultValues: blank() })
  const parcels = useFieldArray({ control: form.control, name: 'parcels' })
  const parcelValues = useWatch({ control: form.control, name: 'parcels' }) ?? []
  const qty = useWatch({ control: form.control, name: 'items' }) ?? {}

  const parcelCharge = (p: ParcelValues) => {
    if (p.mode === 'kg') return perKg && Number(p.weight) > 0 ? Math.round(Number(p.weight) * perKg + 1e-9) : 0
    const s = sizes.find((x) => x.id === p.size)
    return s ? Number(s.price.amount) : 0
  }
  // Preview only: the server computes the real total (kg price rounded half-up per Parcel).
  const preview =
    parcelValues.reduce((sum, p) => sum + parcelCharge(p), 0) +
    items.reduce((sum, i) => sum + (qty[i.id] ?? 0) * Number(i.unit_price.amount), 0)
  const itemCount = Object.values(qty).reduce((a, b) => a + b, 0)

  const submit = useMutation({
    mutationFn: (v: Values) => {
      const attributes: Record<string, unknown> = {
        idempotency_key: key,
        sender_name: v.sender_name,
        sender_phone: v.sender_phone,
        receiver_name: v.receiver_name,
        receiver_phone: v.receiver_phone,
        destination_station_id: v.destination,
        payment_method: v.method,
        parcels: v.parcels.map((p) =>
          p.mode === 'kg' ? { measurement_type: 'kg', weight_kg: p.weight } : { measurement_type: 'size', size_class_id: p.size },
        ),
        sale_items: Object.entries(v.items)
          .filter(([, q]) => q > 0)
          .map(([sale_item_id, quantity]) => ({ sale_item_id, quantity })),
      }
      if (v.declared) attributes.declared_value = { amount: v.declared, currency: 'KHR' }
      return create('/shipments', 'shipment', attributes)
    },
    onSuccess: (s) => {
      toast.success(`Invoice #${s.invoice_no} created`)
      return qc.invalidateQueries({ queryKey: apiKey('shipments') })
    },
  })

  const again = () => {
    const { method, destination } = form.getValues()
    submit.reset()
    setKey(crypto.randomUUID())
    form.reset(blank(method, destination))
  }

  const done = submit.data
  if (done) {
    const to = stationsQ.data?.find((s) => s.id === done.destination_station_id)
    return (
      <Page title="Shipment created" subtitle="Payment taken. Hand the printed Invoice to the Sender.">
        <Card className="max-w-xl">
          <p className="text-[13px] text-ink-soft">Invoice Number</p>
          <p id="invoice-no" className="tabular mt-0.5 text-[40px] leading-none font-semibold tracking-[-0.02em]">
            #{done.invoice_no}
          </p>
          <dl className="grid grid-cols-2 gap-4 border-t border-thread pt-4 text-sm">
            <div>
              <dt className="text-xs text-ink-soft">Sender</dt>
              <dd className="mt-0.5 font-medium">{done.sender_name}</dd>
            </div>
            <div>
              <dt className="text-xs text-ink-soft">Receiver</dt>
              <dd className="mt-0.5 font-medium">{done.receiver_name}</dd>
            </div>
            {to && (
              <div>
                <dt className="text-xs text-ink-soft">Destination Station</dt>
                <dd className="mt-0.5 font-medium">{to.name_en}</dd>
              </div>
            )}
            <div>
              <dt className="text-xs text-ink-soft">Status</dt>
              <dd className="mt-0.5 font-medium">{done.status_label_en}</dd>
            </div>
          </dl>
          <div className="flex items-baseline justify-between border-t border-thread pt-4">
            <span className="text-sm text-ink-soft">Shipment Total paid</span>
            <Num className="text-xl font-semibold">
              <span id="invoice-total">{money(done.shipment_total)}</span>
            </Num>
          </div>
          <div className="no-print flex gap-2 pt-1">
            <Button icon={<Printer aria-hidden className="size-4" />} onClick={() => window.print()}>
              Print Invoice
            </Button>
            <Button id="new-another" variant="outline" onClick={again}>
              New Shipment
            </Button>
          </div>
        </Card>
      </Page>
    )
  }

  const c = form.control
  return (
    <Page title="New Shipment">
      <Err error={loadError} />
      <form
        id="shipment-form"
        noValidate
        onSubmit={form.handleSubmit((v) => submit.mutate(v))}
        className="grid items-start gap-5 lg:grid-cols-[minmax(0,1fr)_320px]"
      >
        <div className="min-w-0 space-y-5">
          <Card title="Sender and Receiver">
            <div className="grid gap-4 sm:grid-cols-2">
              <FormField control={c} name="sender_name" label="Sender name">
                {(f) => <Input {...f} autoFocus autoComplete="off" />}
              </FormField>
              <FormField control={c} name="sender_phone" label="Sender phone">
                {(f) => <Input {...f} inputMode="tel" autoComplete="off" className="tabular" />}
              </FormField>
              <FormField control={c} name="receiver_name" label="Receiver name">
                {(f) => <Input {...f} autoComplete="off" />}
              </FormField>
              <FormField control={c} name="receiver_phone" label="Receiver phone">
                {(f) => <Input {...f} inputMode="tel" autoComplete="off" className="tabular" />}
              </FormField>
              <FormField control={c} name="destination" label="Destination Station">
                {(f) => (
                  <Combobox
                    id={f.id}
                    value={f.value}
                    onChange={f.onChange}
                    invalid={f['aria-invalid']}
                    placeholder={stationsQ.isPending ? 'Loading Stations…' : 'Choose a Station…'}
                    searchPlaceholder="Search Stations…"
                    empty="No Station by that name."
                    options={stations.map((s) => ({ value: s.id, label: s.name_en, keywords: [s.name_km ?? ''] }))}
                  />
                )}
              </FormField>
              <FormField control={c} name="declared" label="Declared value" description="Optional, in riel (៛).">
                {(f) => <Input {...f} inputMode="numeric" autoComplete="off" className="tabular" />}
              </FormField>
            </div>
          </Card>

          <Card
            title="Parcels"
            description={
              perKg ? (
                <>
                  By weight: <span className="tabular">{riel(perKg)}</span> per kg
                </>
              ) : undefined
            }
            flush
          >
            <ol>
              {parcels.fields.map((row, i) => {
                const p = parcelValues[i] ?? row
                return (
                  <li key={row.id} className="flex flex-wrap items-start gap-3 border-b border-thread px-5 py-4">
                    <span className="tabular mt-6 grid size-9 shrink-0 place-items-center rounded-weave bg-sunk text-sm font-medium text-ink-soft">
                      {i + 1}
                    </span>
                    <FormField control={c} name={`parcels.${i}.mode`} label="Charge by" className="w-52">
                      {(f) => (
                        <Segmented id={f.id} value={f.value} onChange={f.onChange} options={MODES} aria-label={`Parcel ${i + 1} charge by`} />
                      )}
                    </FormField>
                    {p.mode === 'kg' ? (
                      <FormField control={c} name={`parcels.${i}.weight`} label="Weight (kg)" className="w-40">
                        {(f) => <Input {...f} placeholder="e.g. 1.01" inputMode="decimal" autoComplete="off" className="tabular" />}
                      </FormField>
                    ) : (
                      <FormField control={c} name={`parcels.${i}.size`} label="Size Class" className="w-60">
                        {(f) => (
                          <Combobox
                            id={f.id}
                            value={f.value}
                            onChange={f.onChange}
                            invalid={f['aria-invalid']}
                            searchPlaceholder="Search Size Classes…"
                            options={sizes.map((s) => ({ value: s.id, label: s.name_en, hint: money(s.price), keywords: [s.name_km ?? ''] }))}
                          />
                        )}
                      </FormField>
                    )}
                    <Num className="mt-8 ml-auto text-sm font-medium text-ink-soft">{riel(parcelCharge(p))}</Num>
                    {parcels.fields.length > 1 && (
                      <Button
                        variant="ghost"
                        size="icon"
                        className="mt-6 text-ink-faint hover:text-madder-deep"
                        aria-label={`Remove Parcel ${i + 1}`}
                        onClick={() => parcels.remove(i)}
                      >
                        <Trash2 aria-hidden className="size-4" />
                      </Button>
                    )}
                  </li>
                )
              })}
            </ol>
            <div className="px-5 py-3">
              <Button
                id="add-parcel"
                variant="ghost"
                size="sm"
                icon={<Plus aria-hidden className="size-4" />}
                onClick={() => parcels.append(blankParcel())}
              >
                Add Parcel
              </Button>
            </div>
          </Card>

          <Card title="Sale Items" description="Counter items sold with this Shipment." flush>
            {itemsQ.isSuccess && items.length === 0 ? (
              <p className="px-5 py-4 text-sm text-ink-soft">No Sale Items on offer.</p>
            ) : (
              <ul>
                {items.map((i) => {
                  const n = qty[i.id] ?? 0
                  const setN = (v: number) =>
                    form.setValue('items', { ...form.getValues('items'), [i.id]: Math.max(0, Math.floor(v) || 0) }, { shouldDirty: true })
                  return (
                    <li key={i.id} className="flex items-center gap-4 border-t border-thread px-5 py-3 first:border-t-0">
                      <Bilingual className="flex-1" en={i.name_en} km={i.name_km} />
                      <Num className="text-sm text-ink-soft">{money(i.unit_price)}</Num>
                      <div className="flex items-center rounded-weave border border-thread-strong bg-surface">
                        <button
                          type="button"
                          aria-label={`One fewer ${i.name_en}`}
                          disabled={n === 0}
                          onClick={() => setN(n - 1)}
                          className="grid size-8 place-items-center text-ink-soft transition-colors hover:text-ink disabled:opacity-35"
                        >
                          <Minus aria-hidden className="size-3.5" />
                        </button>
                        <input
                          type="number"
                          min={0}
                          aria-label={`${i.name_en} quantity`}
                          className="tabular h-8 w-10 [appearance:textfield] border-x border-thread bg-transparent text-center text-sm focus:outline-none [&::-webkit-inner-spin-button]:appearance-none"
                          value={n}
                          onChange={(e) => setN(Number(e.target.value))}
                        />
                        <button
                          type="button"
                          aria-label={`One more ${i.name_en}`}
                          onClick={() => setN(n + 1)}
                          className="grid size-8 place-items-center text-ink-soft transition-colors hover:text-ink"
                        >
                          <Plus aria-hidden className="size-3.5" />
                        </button>
                      </div>
                    </li>
                  )
                })}
              </ul>
            )}
          </Card>
        </div>

        <aside className="lg:sticky lg:top-6">
          <Card title="Payment">
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between">
                <dt className="text-ink-soft">Parcels</dt>
                <dd className="tabular">{parcels.fields.length}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-ink-soft">Sale Items</dt>
                <dd className="tabular">{itemCount}</dd>
              </div>
            </dl>
            <div className="border-t border-thread pt-4">
              <p className="text-xs text-ink-soft">Estimated Shipment Total</p>
              <p id="preview-total" className="tabular mt-0.5 text-[28px] leading-tight font-semibold tracking-[-0.015em]">
                {preview.toLocaleString('en-US')} ៛
              </p>
              <p className="mt-1 text-xs text-ink-faint">The server works out the final amount.</p>
            </div>
            <FormField control={c} name="method" label="Method">
              {(f) => <Segmented id={f.id} value={f.value} onChange={f.onChange} options={METHODS} aria-label="Payment method" />}
            </FormField>
            <Button id="submit-shipment" type="submit" busy={submit.isPending} className="h-11 w-full text-[15px]">
              {submit.isPending ? 'Saving…' : 'Take Payment & create'}
            </Button>
            <Err error={submit.error} />
          </Card>
        </aside>
      </form>
    </Page>
  )
}
