import { useEffect, useState } from 'react'
import { create, list, remove, update, type Rec } from '#/lib/api'
import { Card, Err, Field, Page, Table, btn, btn2, input, useAction } from '#/components/ui'

export function Network() {
  const [locations, setLocations] = useState<Rec[]>([])
  const [stations, setStations] = useState<Rec[]>([])
  const [routes, setRoutes] = useState<Rec[]>([])
  const [loc, setLoc] = useState({ name_en: '', name_km: '' })
  const [st, setSt] = useState({ location_id: '', name_en: '', name_km: '' })
  const [rt, setRt] = useState({ origin: '', destination: '' })
  const load = () => {
    list('/locations').then(setLocations)
    list('/stations').then(setStations)
    list('/routes').then(setRoutes)
  }
  useEffect(() => { load() }, [])
  const name = (id: string) => locations.find((l) => l.id === id)?.name_en ?? id
  const addLoc = useAction(() => create('/locations', 'location', loc), () => { setLoc({ name_en: '', name_km: '' }); load() })
  const delLoc = useAction((id: string) => remove(`/locations/${id}`), load)
  const addSt = useAction(() => create('/stations', 'station', st), () => { setSt({ location_id: '', name_en: '', name_km: '' }); load() })
  const toggleSt = useAction((s: Rec) => update(`/stations/${s.id}`, 'station', { active: !s.active }), load)
  const addRt = useAction(() => create('/routes', 'route', { origin_location_id: rt.origin, destination_location_id: rt.destination }), load)
  const delRt = useAction((id: string) => remove(`/routes/${id}`), load)
  const pick = (v: string, set: (v: string) => void) => (
    <select className={input} value={v} onChange={(e) => set(e.target.value)}>
      <option value="">Choose…</option>
      {locations.map((l) => <option key={l.id} value={l.id}>{l.name_en}</option>)}
    </select>
  )
  return (
    <Page title="Stations & routes">
      <Card title="Locations">
        <Err error={addLoc.error ?? delLoc.error} />
        <Table head={['English', 'Khmer', '']}
          rows={locations.map((l) => [l.name_en, l.name_km, <button key="d" className={btn2} onClick={() => delLoc.run(l.id)}>Delete</button>])} />
        <div className="flex items-end gap-2">
          <Field label="English"><input className={input} value={loc.name_en} onChange={(e) => setLoc({ ...loc, name_en: e.target.value })} /></Field>
          <Field label="Khmer"><input className={input} value={loc.name_km} onChange={(e) => setLoc({ ...loc, name_km: e.target.value })} /></Field>
          <button className={btn} disabled={!loc.name_en || !loc.name_km || addLoc.busy} onClick={() => addLoc.run()}>Add</button>
        </div>
      </Card>
      <Card title="Stations">
        <Err error={addSt.error ?? toggleSt.error} />
        <Table head={['Station', 'Location', 'Active', '']}
          rows={stations.map((s) => [s.name_en, name(s.location_id), s.active ? 'Yes' : 'No',
            <button key="t" className={btn2} onClick={() => toggleSt.run(s)}>{s.active ? 'Deactivate' : 'Activate'}</button>])} />
        <div className="grid grid-cols-4 items-end gap-2">
          <Field label="Location">{pick(st.location_id, (v) => setSt({ ...st, location_id: v }))}</Field>
          <Field label="English"><input className={input} value={st.name_en} onChange={(e) => setSt({ ...st, name_en: e.target.value })} /></Field>
          <Field label="Khmer"><input className={input} value={st.name_km} onChange={(e) => setSt({ ...st, name_km: e.target.value })} /></Field>
          <button className={btn} disabled={!st.location_id || !st.name_en || !st.name_km || addSt.busy} onClick={() => addSt.run()}>Add</button>
        </div>
      </Card>
      <Card title="Routes (one direction each)">
        <Err error={addRt.error ?? delRt.error} />
        <Table head={['From', 'To', '']}
          rows={routes.map((r) => [name(r.origin_location_id), name(r.destination_location_id),
            <button key="d" className={btn2} onClick={() => delRt.run(r.id)}>Delete</button>])} />
        <div className="grid grid-cols-3 items-end gap-2">
          <Field label="From">{pick(rt.origin, (v) => setRt({ ...rt, origin: v }))}</Field>
          <Field label="To">{pick(rt.destination, (v) => setRt({ ...rt, destination: v }))}</Field>
          <button className={btn} disabled={!rt.origin || !rt.destination || addRt.busy} onClick={() => addRt.run()}>Add</button>
        </div>
      </Card>
    </Page>
  )
}
