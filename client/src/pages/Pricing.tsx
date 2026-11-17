import { useEffect, useState } from 'react'
import { create, list, money, rawGet, update, when, type Rec } from '#/lib/api'
import { Card, Err, Field, Page, Table, btn, btn2, input, useAction } from '#/components/ui'

type Cat = { path: string; type: string; title: string; priceKey: 'price' | 'unit_price' }
const CATS: Cat[] = [
  { path: '/size-classes', type: 'size-class', title: 'Size classes', priceKey: 'price' },
  { path: '/sale-items', type: 'sale-item', title: 'Sale items', priceKey: 'unit_price' },
]

function Catalogue({ cat }: { cat: Cat }) {
  const [rows, setRows] = useState<Rec[]>([])
  const [f, setF] = useState({ name_en: '', name_km: '', price: '' })
  const [prices, setPrices] = useState<Record<string, string>>({})
  const load = () => list(cat.path).then(setRows)
  useEffect(() => { load() }, [])
  const add = useAction(
    () => create(cat.path, cat.type, { name_en: f.name_en, name_km: f.name_km, [cat.priceKey]: { amount: f.price, currency: 'KHR' } }),
    () => { setF({ name_en: '', name_km: '', price: '' }); load() })
  const setPrice = useAction((id: string) => update(`${cat.path}/${id}/price`, cat.type, { [cat.priceKey]: { amount: prices[id], currency: 'KHR' } }), load)
  const toggle = useAction((r: Rec) => update(`${cat.path}/${r.id}`, cat.type, { active: !r.active }), load)
  return (
    <Card title={cat.title}>
      <Err error={add.error ?? setPrice.error ?? toggle.error} />
      <Table head={['English', 'Khmer', 'Price', 'New price', 'Active']}
        rows={rows.map((r) => [
          r.name_en, r.name_km, money(r[cat.priceKey]),
          <span key="p" className="flex gap-1">
            <input className={`${input} w-24`} inputMode="numeric" value={prices[r.id] ?? ''} onChange={(e) => setPrices({ ...prices, [r.id]: e.target.value })} />
            <button className={btn2} disabled={!prices[r.id] || setPrice.busy} onClick={() => setPrice.run(r.id)}>Set</button>
          </span>,
          <button key="t" className={btn2} disabled={toggle.busy} onClick={() => toggle.run(r)}>{r.active ? 'Deactivate' : 'Activate'}</button>,
        ])} />
      <div className="grid grid-cols-4 items-end gap-2">
        <Field label="English"><input className={input} value={f.name_en} onChange={(e) => setF({ ...f, name_en: e.target.value })} /></Field>
        <Field label="Khmer"><input className={input} value={f.name_km} onChange={(e) => setF({ ...f, name_km: e.target.value })} /></Field>
        <Field label="Price (KHR)"><input className={input} inputMode="numeric" value={f.price} onChange={(e) => setF({ ...f, price: e.target.value })} /></Field>
        <button className={btn} disabled={add.busy || !f.name_en || !f.name_km || !f.price} onClick={() => add.run()}>Add</button>
      </div>
    </Card>
  )
}

export function Pricing() {
  const [perKg, setPerKg] = useState<any>(null)
  const [next, setNext] = useState('')
  const [fee, setFee] = useState({ cap: '', percent: '' })
  const [changes, setChanges] = useState<Rec[]>([])
  const load = () => {
    rawGet('/pricing/current').then((j) => setPerKg(j.data?.attributes ?? j.data ?? j)).catch(() => {})
    list('/price-changes').then((r) => setChanges([...r].reverse().slice(0, 20))).catch(() => {})
  }
  useEffect(() => { load() }, [])
  const savePerKg = useAction(() => create('/pricing/price-per-kg', 'price-per-kg', { price_per_kg: { amount: next, currency: 'KHR' } }), () => { setNext(''); load() })
  const saveFee = useAction(() => create('/pricing/cancellation-fee', 'cancellation-fee', { cap: { amount: fee.cap, currency: 'KHR' }, percent: fee.percent }), load)
  return (
    <Page title="Pricing">
      <Card title="Price per kg">
        <Err error={savePerKg.error} />
        <p className="text-sm">Current: <b>{money(perKg?.price_per_kg)}</b> per kg</p>
        <div className="flex gap-2">
          <input className={`${input} w-40`} inputMode="numeric" placeholder="New price (KHR)" value={next} onChange={(e) => setNext(e.target.value)} />
          <button className={btn} disabled={!next || savePerKg.busy} onClick={() => savePerKg.run()}>Save</button>
        </div>
      </Card>
      <Card title="Cancellation fee">
        <Err error={saveFee.error} />
        <p className="text-sm text-slate-500">Fee is a percent of the Shipment Total, capped at a fixed amount.</p>
        <div className="flex gap-2">
          <input className={`${input} w-40`} inputMode="numeric" placeholder="Cap (KHR)" value={fee.cap} onChange={(e) => setFee({ ...fee, cap: e.target.value })} />
          <input className={`${input} w-32`} inputMode="numeric" placeholder="Percent" value={fee.percent} onChange={(e) => setFee({ ...fee, percent: e.target.value })} />
          <button className={btn} disabled={!fee.cap || !fee.percent || saveFee.busy} onClick={() => saveFee.run()}>Save</button>
        </div>
      </Card>
      {CATS.map((c) => <Catalogue key={c.path} cat={c} />)}
      <Card title="Recent price changes">
        <Table head={['When', 'Kind', 'New price']} rows={changes.map((c) => [when(c.inserted_at), c.kind, money(c.price)])} />
      </Card>
    </Page>
  )
}
