import { useEffect, useState } from 'react'
import { create, list, update, type Rec } from '#/lib/api'
import { Card, Err, Field, Page, Table, btn, btn2, input, useAction } from '#/components/ui'

export function StationSettings() {
  const [stations, setStations] = useState<Rec[]>([])
  const [days, setDays] = useState<Record<string, string>>({})
  const load = () => list('/stations').then(setStations)
  useEffect(() => { load() }, [])
  const approval = useAction((s: Rec) => update(`/stations/${s.id}/cancellation-approval`, 'station', { cancellation_requires_approval: !s.cancellation_requires_approval }), load)
  const threshold = useAction((s: Rec) => update(`/stations/${s.id}/overdue-threshold`, 'station', { overdue_threshold_days: Number(days[s.id]) }), load)
  return (
    <Page title="Station settings">
      <Err error={approval.error ?? threshold.error} />
      <Card>
        <Table head={['Station', 'Cancel needs approval', 'Overdue after (days)', '']}
          rows={stations.map((s) => [
            s.name_en,
            <button key="a" className={btn2} disabled={approval.busy} onClick={() => approval.run(s)}>{s.cancellation_requires_approval ? 'Yes — turn off' : 'No — turn on'}</button>,
            s.overdue_threshold_days,
            <span key="d" className="flex gap-1">
              <input className={`${input} w-20`} inputMode="numeric" value={days[s.id] ?? ''} onChange={(e) => setDays({ ...days, [s.id]: e.target.value })} />
              <button className={btn2} disabled={!days[s.id] || threshold.busy} onClick={() => threshold.run(s)}>Set</button>
            </span>,
          ])} />
      </Card>
    </Page>
  )
}

export function Users() {
  const [users, setUsers] = useState<Rec[]>([])
  const [stations, setStations] = useState<Rec[]>([])
  const [f, setF] = useState({ email: '', password: '', role: 'staff', station_id: '' })
  const load = () => { list('/users').then(setUsers); list('/stations').then(setStations) }
  useEffect(() => { load() }, [])
  const add = useAction(
    () => create('/users', 'user', { email: f.email, password: f.password, password_confirmation: f.password, role: f.role, station_id: f.role === 'admin' ? null : f.station_id }),
    () => { setF({ email: '', password: '', role: 'staff', station_id: '' }); load() })
  const change = useAction((u: Rec, attrs: object) => update(`/users/${u.id}`, 'user', attrs), load)
  return (
    <Page title="Users">
      <Err error={add.error ?? change.error} />
      <Card>
        <Table head={['Email', 'Role', 'Station']}
          rows={users.map((u) => [
            u.email,
            <select key="r" className={input} value={u.role} onChange={(e) => change.run(u, { role: e.target.value })}>
              {['staff', 'supervisor', 'admin'].map((r) => <option key={r}>{r}</option>)}
            </select>,
            <select key="s" className={input} value={u.station_id ?? ''} onChange={(e) => change.run(u, { station_id: e.target.value || null })}>
              <option value="">—</option>
              {stations.map((s) => <option key={s.id} value={s.id}>{s.name_en}</option>)}
            </select>,
          ])} />
      </Card>
      <Card title="New user">
        <div className="grid grid-cols-5 items-end gap-2">
          <Field label="Email"><input className={input} value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} /></Field>
          <Field label="Password"><input type="password" className={input} value={f.password} onChange={(e) => setF({ ...f, password: e.target.value })} /></Field>
          <Field label="Role">
            <select className={input} value={f.role} onChange={(e) => setF({ ...f, role: e.target.value })}>
              {['staff', 'supervisor', 'admin'].map((r) => <option key={r}>{r}</option>)}
            </select>
          </Field>
          <Field label="Station">
            <select className={input} disabled={f.role === 'admin'} value={f.station_id} onChange={(e) => setF({ ...f, station_id: e.target.value })}>
              <option value="">—</option>
              {stations.map((s) => <option key={s.id} value={s.id}>{s.name_en}</option>)}
            </select>
          </Field>
          <button className={btn} disabled={add.busy || !f.email || !f.password} onClick={() => add.run()}>Create</button>
        </div>
      </Card>
    </Page>
  )
}
