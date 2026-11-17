import { useEffect, useState } from 'react'
import { create, list, money, type Rec } from '#/lib/api'
import { Card, Err, Field, Page, btn, btn2, input, useAction } from '#/components/ui'

type ParcelRow = { mode: 'kg' | 'size'; weight: string; size: string }

export function NewShipment({ stationId }: { stationId: string | null }) {
  const [stations, setStations] = useState<Rec[]>([])
  const [sizes, setSizes] = useState<Rec[]>([])
  const [items, setItems] = useState<Rec[]>([])
  const [perKg, setPerKg] = useState<number | null>(null)
  const [key, setKey] = useState(() => crypto.randomUUID())
  const [f, setF] = useState({ sender_name: '', sender_phone: '', receiver_name: '', receiver_phone: '', destination: '', method: 'cash', declared: '' })
  const [parcels, setParcels] = useState<ParcelRow[]>([{ mode: 'kg', weight: '', size: '' }])
  const [qty, setQty] = useState<Record<string, number>>({})
  const [done, setDone] = useState<Rec | null>(null)
  const [loadError, setLoadError] = useState<unknown>(null)

  useEffect(() => {
    Promise.all([list('/stations'), list('/size-classes'), list('/sale-items'), list('/pricing/current')])
      .then(([st, sz, si, pr]) => {
        setStations(st.filter((s) => s.active && s.id !== stationId))
        setSizes(sz.filter((s) => s.active))
        setItems(si.filter((s) => s.active))
        setPerKg(pr[0] ? Number(pr[0].price_per_kg.amount) : null)
      })
      .catch(setLoadError)
  }, [stationId])

  // Preview only: the server computes the real total (kg price rounded half-up per Parcel).
  const preview =
    parcels.reduce((sum, p) => {
      if (p.mode === 'kg') return sum + (perKg && p.weight ? Math.round(Number(p.weight) * perKg + 1e-9) : 0)
      const s = sizes.find((x) => x.id === p.size)
      return sum + (s ? Number(s.price.amount) : 0)
    }, 0) +
    items.reduce((sum, i) => sum + (qty[i.id] ?? 0) * Number(i.unit_price.amount), 0)

  const submit = useAction(async () => {
    const attributes: Record<string, unknown> = {
      idempotency_key: key,
      sender_name: f.sender_name,
      sender_phone: f.sender_phone,
      receiver_name: f.receiver_name,
      receiver_phone: f.receiver_phone,
      destination_station_id: f.destination,
      payment_method: f.method,
      parcels: parcels.map((p) =>
        p.mode === 'kg' ? { measurement_type: 'kg', weight_kg: p.weight } : { measurement_type: 'size', size_class_id: p.size },
      ),
      sale_items: Object.entries(qty).filter(([, q]) => q > 0).map(([sale_item_id, quantity]) => ({ sale_item_id, quantity })),
    }
    if (f.declared) attributes.declared_value = { amount: f.declared, currency: 'KHR' }
    setDone(await create('/shipments', 'shipment', attributes))
  })

  const reset = () => {
    setDone(null)
    setKey(crypto.randomUUID())
    setF({ ...f, sender_name: '', sender_phone: '', receiver_name: '', receiver_phone: '', declared: '' })
    setParcels([{ mode: 'kg', weight: '', size: '' }])
    setQty({})
  }

  if (done)
    return (
      <Page title="Invoice">
        <Card>
          <p id="invoice-no" className="text-2xl font-semibold">Invoice #{done.invoice_no}</p>
          <p className="text-sm text-slate-600">{done.sender_name} → {done.receiver_name} · {done.status_label_en}</p>
          <p id="invoice-total" className="text-lg">Total paid: {money(done.shipment_total)}</p>
          <div className="flex gap-2">
            <button className={btn} onClick={() => window.print()}>Print</button>
            <button id="new-another" className={btn2} onClick={reset}>New shipment</button>
          </div>
        </Card>
      </Page>
    )

  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Page title="New Shipment">
      <Err error={loadError} />
      <form id="shipment-form" className="space-y-4" onSubmit={(e) => { e.preventDefault(); submit.run() }}>
        <Card title="Sender and receiver">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Sender name"><input required className={input} value={f.sender_name} onChange={set('sender_name')} /></Field>
            <Field label="Sender phone"><input required className={input} value={f.sender_phone} onChange={set('sender_phone')} /></Field>
            <Field label="Receiver name"><input required className={input} value={f.receiver_name} onChange={set('receiver_name')} /></Field>
            <Field label="Receiver phone"><input required className={input} value={f.receiver_phone} onChange={set('receiver_phone')} /></Field>
            <Field label="Destination station">
              <select required className={input} value={f.destination} onChange={set('destination')}>
                <option value="">Choose…</option>
                {stations.map((s) => <option key={s.id} value={s.id}>{s.name_en}</option>)}
              </select>
            </Field>
            <Field label="Declared value (៛, optional)"><input inputMode="numeric" className={input} value={f.declared} onChange={set('declared')} /></Field>
          </div>
        </Card>

        <Card title="Parcels">
          {parcels.map((p, i) => (
            <div key={i} className="flex flex-wrap items-end gap-2">
              <select className={`${input} w-32`} value={p.mode}
                onChange={(e) => setParcels(parcels.map((x, j) => (j === i ? { ...x, mode: e.target.value as 'kg' | 'size' } : x)))}>
                <option value="kg">By weight</option>
                <option value="size">By size</option>
              </select>
              {p.mode === 'kg' ? (
                <input required placeholder="kg, e.g. 1.01" inputMode="decimal" className={`${input} w-40`} value={p.weight}
                  onChange={(e) => setParcels(parcels.map((x, j) => (j === i ? { ...x, weight: e.target.value } : x)))} />
              ) : (
                <select required className={`${input} w-56`} value={p.size}
                  onChange={(e) => setParcels(parcels.map((x, j) => (j === i ? { ...x, size: e.target.value } : x)))}>
                  <option value="">Size class…</option>
                  {sizes.map((s) => <option key={s.id} value={s.id}>{s.name_en} — {money(s.price)}</option>)}
                </select>
              )}
              {parcels.length > 1 && <button type="button" className={btn2} onClick={() => setParcels(parcels.filter((_, j) => j !== i))}>Remove</button>}
            </div>
          ))}
          <button type="button" id="add-parcel" className={btn2} onClick={() => setParcels([...parcels, { mode: 'kg', weight: '', size: '' }])}>Add parcel</button>
        </Card>

        <Card title="Counter items">
          {items.length === 0 && <p className="text-sm text-slate-500">No items for sale.</p>}
          {items.map((i) => (
            <div key={i.id} className="flex items-center justify-between text-sm">
              <span>{i.name_en} — {money(i.unit_price)}</span>
              <input type="number" min={0} className={`${input} w-20`} value={qty[i.id] ?? 0}
                onChange={(e) => setQty({ ...qty, [i.id]: Number(e.target.value) })} />
            </div>
          ))}
        </Card>

        <Card>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-xs text-slate-500">Estimated total (the server computes the final amount)</p>
              <p id="preview-total" className="text-xl font-semibold">{preview.toLocaleString('en-US')} ៛</p>
            </div>
            <div className="flex items-end gap-2">
              <select className={`${input} w-40`} value={f.method} onChange={set('method')}>
                <option value="cash">Cash</option>
                <option value="bank_transfer">Bank transfer</option>
                <option value="qr">QR</option>
              </select>
              <button id="submit-shipment" className={btn} disabled={submit.busy}>{submit.busy ? 'Saving…' : 'Take payment & create'}</button>
            </div>
          </div>
          <Err error={submit.error} />
        </Card>
      </form>
    </Page>
  )
}
