import { useEffect, useState } from 'react'
import { rawGet, money } from '#/lib/api'
import { Card, Err, Page, Table, btn, input } from '#/components/ui'

// Report days are Asia/Phnom_Penh (UTC+7) days, sent to the API as UTC instants (ADR-0005).
const PP_OFFSET_MS = 7 * 3600e3
const ppDay = (ms: number) => new Date(ms + PP_OFFSET_MS).toISOString().slice(0, 10)
const today = () => ppDay(Date.now())
const monthStart = () => today().slice(0, 8) + '01'
const tomorrow = () => ppDay(Date.now() + 864e5)
const dayStartUtc = (day: string) => new Date(`${day}T00:00:00+07:00`).toISOString()

function useReport(kind: 'cash' | 'cancellations') {
  const [from, setFrom] = useState(monthStart())
  const [to, setTo] = useState(tomorrow())
  const [rows, setRows] = useState<any[]>([])
  const [error, setError] = useState<unknown>(null)
  const load = () =>
    rawGet(`/reports/${kind}?from=${encodeURIComponent(dayStartUtc(from))}&to=${encodeURIComponent(dayStartUtc(to))}`).then((r) => { setRows(Array.isArray(r) ? r : []); setError(null) }).catch(setError)
  useEffect(() => { load() }, [])
  return { from, setFrom, to, setTo, rows, error, load }
}

function Range({ r }: { r: ReturnType<typeof useReport> }) {
  return (
    <div className="flex items-end gap-2">
      <label className="text-sm">From <input type="date" className={input} value={r.from} onChange={(e) => r.setFrom(e.target.value)} /></label>
      <label className="text-sm">To (exclusive) <input type="date" className={input} value={r.to} onChange={(e) => r.setTo(e.target.value)} /></label>
      <button className={btn} onClick={r.load}>Run</button>
    </div>
  )
}

const m = (currency: string, amount: string) => money({ currency, amount })

export function CashReport() {
  const r = useReport('cash')
  return (
    <Page title="Cash report" action={<Range r={r} />}>
      <Err error={r.error} />
      <Card>
        <Table head={['Staff', 'Cash taken', 'Refunded', 'Net cash']}
          rows={r.rows.map((x) => [x.email, m(x.currency, x.cash_taken), m(x.currency, x.cash_refunded), m(x.currency, x.net_cash)])} />
      </Card>
    </Page>
  )
}

export function CancellationReport() {
  const r = useReport('cancellations')
  return (
    <Page title="Cancellation report" action={<Range r={r} />}>
      <Err error={r.error} />
      <Card>
        <Table head={['Staff', 'Pending', 'Approved', 'Rejected', 'Refunded', 'Fees kept']}
          rows={r.rows.map((x) => [x.email, x.pending, x.approved, x.rejected, m(x.currency, x.refunded), m(x.currency, x.fees_kept)])} />
      </Card>
    </Page>
  )
}
