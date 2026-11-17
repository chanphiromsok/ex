import { useEffect, useState } from 'react'
import { create, get, list, money, update, when, type Rec } from '#/lib/api'
import type { Session } from '#/lib/auth'
import { Card, Err, Field, Page, Table, btn, btn2, input, useAction } from '#/components/ui'

export function Shipments({ session }: { session: Session }) {
  const [rows, setRows] = useState<Rec[]>([])
  const [q, setQ] = useState('')
  const [selected, setSelected] = useState<string | null>(null)
  const [error, setError] = useState<unknown>(null)

  const load = () => list('/shipments').then(setRows).catch(setError)
  useEffect(() => { load() }, [])

  const needle = q.trim().toLowerCase()
  const shown = rows.filter((s) =>
    !needle || String(s.invoice_no) === needle.replace('#', '') ||
    [s.current_receiver_phone, s.receiver_phone, s.sender_phone].some((p) => String(p ?? '').includes(needle.replace(/\D/g, '') || '\0')),
  )

  if (selected) return <Detail id={selected} session={session} onBack={() => { setSelected(null); load() }} />
  return (
    <Page title="Shipments">
      <input id="search" className={input} placeholder="Invoice number or phone number" value={q} onChange={(e) => setQ(e.target.value)} />
      <Err error={error} />
      <Card>
        <Table
          head={['Invoice', 'Sender', 'Receiver', 'Status', 'Total', 'Created']}
          rows={shown.map((s) => [
            <button key="b" className="font-medium underline" onClick={() => setSelected(s.id)}>#{s.invoice_no}</button>,
            s.sender_name, s.current_receiver_name, s.status_label_en, money(s.shipment_total), when(s.inserted_at),
          ])}
        />
      </Card>
    </Page>
  )
}

function Detail({ id, session, onBack }: { id: string; session: Session; onBack: () => void }) {
  const [s, setS] = useState<Rec | null>(null)
  const [error, setError] = useState<unknown>(null)
  const [phone, setPhone] = useState('')
  const [text, setText] = useState('')
  const [corr, setCorr] = useState({ name: '', phone: '', reason: '' })
  const [reason, setReason] = useState('')
  const [inc, setInc] = useState({ kind: 'damaged', note: '' })
  const has = (p: string) => session.permissions.includes(p)

  const load = () =>
    get(`/shipments/${id}?include=parcels,sale_items,payments,status_events,notes,receiver_corrections`).then(setS).catch(setError)
  useEffect(() => { load() }, [id])

  const act = (fn: () => Promise<unknown>) => useAction(fn, load)
  const inTransit = act(() => update(`/shipments/${id}/in-transit`, 'shipment', {}))
  const arrived = act(() => update(`/shipments/${id}/arrived`, 'shipment', {}))
  const collect = act(() => update(`/shipments/${id}/collect`, 'shipment', { receiver_phone: phone }))
  const note = act(async () => { await create('/shipment-notes', 'shipment-note', { shipment_id: id, body: text }); setText('') })
  const correct = act(async () => { await create('/receiver-corrections', 'receiver-correction', { shipment_id: id, ...corr }); setCorr({ name: '', phone: '', reason: '' }) })
  const cancel = act(async () => { await create('/cancellation-requests', 'cancellation-request', { shipment_id: id, reason }); setReason('') })
  const incident = act(async () => { await create('/incidents', 'incident', { shipment_id: id, ...inc }); setInc({ kind: 'damaged', note: '' }) })

  if (!s) return <Page title="Shipment"><Err error={error} /></Page>
  const origin = s.origin_station_id === session.stationId
  const dest = s.destination_station_id === session.stationId
  return (
    <Page title={`Invoice #${s.invoice_no}`} action={<button className={btn2} onClick={onBack}>Back</button>}>
      <Card>
        <p className="text-lg font-medium">{s.status_label_en} <span className="text-sm text-slate-500">· {s.status_label_km}</span></p>
        <p className="text-sm">Sender: {s.sender_name} ({s.sender_phone})</p>
        <p className="text-sm">Receiver: {s.current_receiver_name} ({s.current_receiver_phone})</p>
        <p className="text-sm">Total: {money(s.shipment_total)}</p>
        <Table head={['Parcel', 'Measure', 'Charge']}
          rows={(s.parcels ?? []).map((p: Rec, i: number) => [i + 1, p.measurement_type === 'kg' ? `${p.weight_kg} kg` : 'by size', money(p.chargeable_amount)])} />
        <Table head={['Item', 'Qty', 'Unit']}
          rows={(s.sale_items ?? []).map((p: Rec) => [p.sale_item_id.slice(0, 8), p.quantity, money(p.unit_price)])} />
        <Table head={['Payment', 'Method', 'Amount', 'When']}
          rows={(s.payments ?? []).map((p: Rec) => [p.kind, p.method, money(p.amount), when(p.inserted_at)])} />
        <Table head={['#', 'Status', 'When']}
          rows={(s.status_events ?? []).sort((a: Rec, b: Rec) => a.seq - b.seq).map((e: Rec) => [e.seq, e.status_label_en, when(e.inserted_at)])} />
      </Card>
      <Err error={inTransit.error ?? arrived.error ?? collect.error} />
      <Card title="Movement">
        <div className="flex flex-wrap items-end gap-2">
          {has('shipment.mark_in_transit') && s.status === 'received' && origin && <button id="in-transit" className={btn} disabled={inTransit.busy} onClick={() => inTransit.run()}>Mark in transit</button>}
          {has('shipment.mark_arrived') && s.status === 'in_transit' && dest && <button id="arrived" className={btn} disabled={arrived.busy} onClick={() => arrived.run()}>Mark arrived</button>}
          {has('shipment.collect') && s.status === 'arrived' && dest && (
            <>
              <Field label="Receiver phone"><input id="collect-phone" className={input} value={phone} onChange={(e) => setPhone(e.target.value)} /></Field>
              <button id="collect" className={btn} disabled={collect.busy} onClick={() => collect.run()}>Hand over</button>
            </>
          )}
        </div>
      </Card>
      {has('shipment.add_note') && (
        <Card title="Notes">
          {(s.notes ?? []).map((n: Rec) => <p key={n.id} className="text-sm">• {n.body}</p>)}
          <div className="flex gap-2"><input className={input} value={text} onChange={(e) => setText(e.target.value)} placeholder="Add a note" />
            <button className={btn} disabled={!text || note.busy} onClick={() => note.run()}>Add</button></div>
          <Err error={note.error} />
        </Card>
      )}
      {has('receiver.correct') && (
        <Card title="Correct receiver">
          <div className="grid gap-2 sm:grid-cols-3">
            <input className={input} placeholder="Name" value={corr.name} onChange={(e) => setCorr({ ...corr, name: e.target.value })} />
            <input className={input} placeholder="Phone" value={corr.phone} onChange={(e) => setCorr({ ...corr, phone: e.target.value })} />
            <input className={input} placeholder="Reason" value={corr.reason} onChange={(e) => setCorr({ ...corr, reason: e.target.value })} />
          </div>
          <button className={btn} disabled={correct.busy} onClick={() => correct.run()}>Save correction</button>
          <Err error={correct.error} />
        </Card>
      )}
      {has('cancellation.request') && s.status === 'received' && (
        <Card title="Cancel shipment">
          <input id="cancel-reason" className={input} placeholder="Reason" value={reason} onChange={(e) => setReason(e.target.value)} />
          <button id="cancel" className={btn} disabled={!reason || cancel.busy} onClick={() => cancel.run()}>Request cancellation</button>
          <Err error={cancel.error} />
        </Card>
      )}
      {has('incident.report') && (
        <Card title="Report incident">
          <div className="flex gap-2">
            <select className={`${input} w-56`} value={inc.kind} onChange={(e) => setInc({ ...inc, kind: e.target.value })}>
              {['return_to_sender', 'redirect', 'lost', 'damaged'].map((k) => <option key={k} value={k}>{k.replaceAll('_', ' ')}</option>)}
            </select>
            <input className={input} placeholder="Note" value={inc.note} onChange={(e) => setInc({ ...inc, note: e.target.value })} />
            <button className={btn} disabled={incident.busy} onClick={() => incident.run()}>Report</button>
          </div>
          <Err error={incident.error} />
        </Card>
      )}
    </Page>
  )
}
