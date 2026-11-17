import { useEffect, useState } from 'react'
import { list, money, update, when, type Rec } from '#/lib/api'
import type { Session } from '#/lib/auth'
import { Card, Err, Page, Table, btn, btn2, input, useAction } from '#/components/ui'

function useList(path: string) {
  const [rows, setRows] = useState<Rec[]>([])
  const [error, setError] = useState<unknown>(null)
  const load = () => list(path).then(setRows).catch(setError)
  useEffect(() => { load() }, [path])
  return { rows, error, load }
}

export function Overdue({ session }: { session: Session }) {
  const [station, setStation] = useState('')
  const [stations, setStations] = useState<Rec[]>([])
  useEffect(() => { if (session.role === 'admin') list('/stations').then(setStations) }, [session.role])
  const { rows, error } = useList(`/shipments/overdue${station ? `?destination_station_id=${station}` : ''}`)
  return (
    <Page title="Overdue shipments"
      action={session.role === 'admin' ? (
        <select className={`${input} w-56`} value={station} onChange={(e) => setStation(e.target.value)}>
          <option value="">All stations</option>
          {stations.map((s) => <option key={s.id} value={s.id}>{s.name_en}</option>)}
        </select>) : undefined}>
      <Err error={error} />
      <Card>
        <Table empty="Nothing overdue." head={['Invoice', 'Receiver', 'Phone', 'Status']}
          rows={rows.map((s) => [`#${s.invoice_no}`, s.current_receiver_name, s.current_receiver_phone, s.status_label_en])} />
      </Card>
    </Page>
  )
}

export function Cancellations({ session }: { session: Session }) {
  const { rows, error, load } = useList('/cancellation-requests')
  const [why, setWhy] = useState('')
  const decide = useAction((id: string, how: 'approve' | 'reject') =>
    update(`/cancellation-requests/${id}/${how}`, 'cancellation-request', how === 'reject' ? { decision_reason: why } : {}), load)
  const canApprove = session.permissions.includes('cancellation.approve')
  return (
    <Page title="Cancellations">
      <Err error={error ?? decide.error} />
      {canApprove && <input className={input} placeholder="Reason when rejecting" value={why} onChange={(e) => setWhy(e.target.value)} />}
      <Card>
        <Table head={['Reason', 'Status', 'Fee', 'Refund', 'Requested', '']}
          rows={rows.map((r) => [
            r.reason, r.status, money(r.fee), money(r.refund_amount), when(r.inserted_at),
            canApprove && r.status === 'pending' && r.requested_by_id !== session.userId ? (
              <span key="a" className="flex gap-1">
                <button className={btn} disabled={decide.busy} onClick={() => decide.run(r.id, 'approve')}>Approve</button>
                <button className={btn2} disabled={decide.busy || !why} onClick={() => decide.run(r.id, 'reject')}>Reject</button>
              </span>) : '',
          ])} />
      </Card>
    </Page>
  )
}

export function Incidents({ session }: { session: Session }) {
  const { rows, error, load } = useList('/incidents')
  const [res, setRes] = useState('')
  const resolve = useAction((id: string) => update(`/incidents/${id}/resolve`, 'incident', { resolution: res }), load)
  const can = session.permissions.includes('incident.resolve')
  return (
    <Page title="Incidents">
      <Err error={error ?? resolve.error} />
      {can && <input className={input} placeholder="Resolution (required to resolve)" value={res} onChange={(e) => setRes(e.target.value)} />}
      <Card>
        <Table head={['Kind', 'Note', 'Status', 'Resolution', 'Reported', '']}
          rows={rows.map((i) => [
            i.kind.replaceAll('_', ' '), i.note, i.status, i.resolution ?? '', when(i.inserted_at),
            can && i.status === 'open' ? <button key="r" className={btn} disabled={!res || resolve.busy} onClick={() => resolve.run(i.id)}>Resolve</button> : '',
          ])} />
      </Card>
    </Page>
  )
}
