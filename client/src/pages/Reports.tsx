import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { RefreshCw } from 'lucide-react'
import { money } from '#/lib/api'
import { rawQuery } from '#/lib/queries'
import { dayjs, dayStartUtc, ppDay } from '#/lib/date'
import { Button, Card, Err, Num, Page } from '#/components/kit'
import { DateRangePicker, rangeLabel, type DayRange } from '#/components/form'
import { DataTable, FooterCell, FooterRow, type ColumnDef } from '#/components/data-table'

type Row = Record<string, any>

/**
 * Report days are Asia/Phnom_Penh days (ADR-0005). The picker range is inclusive;
 * the API takes [from, to) as UTC instants, so `to` is the start of the next day.
 */
function useReport(kind: 'cash' | 'cancellations') {
  const [range, setRange] = useState<DayRange>(() => ({
    from: dayjs(ppDay()).startOf('month').format('YYYY-MM-DD'),
    to: ppDay(),
  }))
  const from = dayStartUtc(range.from)
  const to = dayStartUtc(dayjs(range.to).add(1, 'day').format('YYYY-MM-DD'))
  const q = useQuery({
    ...rawQuery<Row[]>(`/reports/${kind}?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`),
    select: (r) => (Array.isArray(r) ? r : []),
  })
  return { range, setRange, q }
}

function RangeBar({ r, id }: { r: ReturnType<typeof useReport>; id: string }) {
  return (
    <div className="flex items-center gap-2">
      <DateRangePicker id={id} value={r.range} onChange={r.setRange} />
      <Button
        variant="outline"
        size="icon"
        aria-label="Refresh report"
        title="Refresh"
        className="shadow-none"
        disabled={r.q.isFetching}
        onClick={() => r.q.refetch()}
      >
        <RefreshCw aria-hidden className={r.q.isFetching ? 'size-4 animate-spin' : 'size-4'} />
      </Button>
    </div>
  )
}

const m = (currency: string, amount: string | number) => money({ currency, amount: String(amount) })
const sum = (rows: Row[], k: string) => rows.reduce((a, x) => a + Number(x[k] ?? 0), 0)
const amountCol = (key: string, header: string, className?: string): ColumnDef<Row> => ({
  id: key,
  accessorFn: (x) => Number(x[key] ?? 0),
  header,
  meta: { align: 'right' },
  cell: ({ row }) => <Num className={className}>{m(row.original.currency, row.original[key])}</Num>,
})
const countCol = (key: string, header: string): ColumnDef<Row> => ({
  id: key,
  accessorFn: (x) => Number(x[key] ?? 0),
  header,
  meta: { align: 'right' },
  cell: ({ getValue }) => <Num>{getValue<number>()}</Num>,
})
const staffCol: ColumnDef<Row> = { id: 'email', accessorFn: (x) => x.email, header: 'Staff' }

export function CashReport() {
  const r = useReport('cash')
  const rows = r.q.data ?? []
  const cur = rows[0]?.currency ?? 'KHR'
  const columns = useMemo(
    () => [
      staffCol,
      amountCol('cash_taken', 'Cash taken'),
      amountCol('cash_refunded', 'Refunded', 'text-madder-deep'),
      amountCol('net_cash', 'Net cash', 'font-medium'),
    ],
    [],
  )
  return (
    <Page
      title="Cash report"
      subtitle={`Cash Payments and refunds per staff member · ${rangeLabel(r.range)}`}
      action={<RangeBar r={r} id="cash-range" />}
    >
      <Err error={r.q.error} />
      <Card flush>
        <DataTable
          id="cash-report"
          columns={columns}
          data={rows}
          loading={r.q.isPending}
          empty="No cash moved in this range."
          initialSort={[{ id: 'net_cash', desc: true }]}
          pageSize={50}
          footer={
            rows.length > 1 && (
              <FooterRow>
                <FooterCell>Total</FooterCell>
                <FooterCell align="right">
                  <Num>{m(cur, sum(rows, 'cash_taken'))}</Num>
                </FooterCell>
                <FooterCell align="right">
                  <Num className="text-madder-deep">{m(cur, sum(rows, 'cash_refunded'))}</Num>
                </FooterCell>
                <FooterCell align="right">
                  <Num>{m(cur, sum(rows, 'net_cash'))}</Num>
                </FooterCell>
              </FooterRow>
            )
          }
        />
      </Card>
    </Page>
  )
}

export function CancellationReport() {
  const r = useReport('cancellations')
  const rows = r.q.data ?? []
  const cur = rows[0]?.currency ?? 'KHR'
  const columns = useMemo(
    () => [
      staffCol,
      countCol('pending', 'Pending'),
      countCol('approved', 'Approved'),
      countCol('rejected', 'Rejected'),
      amountCol('refunded', 'Refunded', 'text-madder-deep'),
      amountCol('fees_kept', 'Fees kept', 'font-medium'),
    ],
    [],
  )
  return (
    <Page
      title="Cancellation report"
      subtitle={`Cancellations per requesting staff member · ${rangeLabel(r.range)}`}
      action={<RangeBar r={r} id="cancellation-range" />}
    >
      <Err error={r.q.error} />
      <Card flush>
        <DataTable
          id="cancellation-report"
          columns={columns}
          data={rows}
          loading={r.q.isPending}
          empty="No Cancellations in this range."
          pageSize={50}
          footer={
            rows.length > 1 && (
              <FooterRow>
                <FooterCell>Total</FooterCell>
                {(['pending', 'approved', 'rejected'] as const).map((k) => (
                  <FooterCell key={k} align="right">
                    <Num>{sum(rows, k)}</Num>
                  </FooterCell>
                ))}
                <FooterCell align="right">
                  <Num className="text-madder-deep">{m(cur, sum(rows, 'refunded'))}</Num>
                </FooterCell>
                <FooterCell align="right">
                  <Num>{m(cur, sum(rows, 'fees_kept'))}</Num>
                </FooterCell>
              </FooterRow>
            )
          }
        />
      </Card>
    </Page>
  )
}
