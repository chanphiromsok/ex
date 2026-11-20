import { when, type Rec } from '#/lib/api'

/**
 * The status weave: a Shipment's life as four warp stripes, filled as each
 * Status Event lands. A Cancellation cuts the band in madder. Labels mirror
 * Ex.Shipping.Status on the server.
 */
export const STEPS = [
  { status: 'received', en: 'Received', km: 'បានទទួល' },
  { status: 'in_transit', en: 'In transit', km: 'កំពុងដឹកជញ្ជូន' },
  { status: 'arrived', en: 'Arrived', km: 'បានមកដល់' },
  { status: 'collected', en: 'Collected', km: 'បានទទួលយកអីវ៉ាន់' },
] as const

const reached = (status: string) => {
  const i = STEPS.findIndex((s) => s.status === status)
  return i === -1 ? 0 : i + 1
}

/** Full band for the Shipment page: each stripe carries its label and when it happened. */
export function StatusWeave({ status, events = [] }: { status: string; events?: Rec[] }) {
  const cancelled = status === 'cancelled'
  const filled = cancelled ? 1 : reached(status)
  const at = (step: string) => events.find((e) => e.status === step)?.inserted_at
  const cut = events.find((e) => e.status === 'cancelled')

  return (
    <div>
      <ol className="grid grid-cols-4 gap-1" aria-label="Shipment progress">
        {STEPS.map((step, i) => {
          const done = i < filled
          const current = !cancelled && i === filled - 1
          const severed = cancelled && i >= 1
          return (
            <li key={step.status} aria-current={current ? 'step' : undefined} className="min-w-0">
              <span
                className={[
                  'block h-2.5 rounded-[3px] transition-colors duration-500 ease-out-expo',
                  done ? 'bg-clay' : severed ? 'bg-madder/15' : 'bg-thread',
                  current && step.status !== 'collected' ? 'weave-hatch' : '',
                ].join(' ')}
              />
              <span className={`mt-2 block truncate text-[13px] font-medium ${done ? 'text-ink' : 'text-ink-faint'}`}>{step.en}</span>
              <span lang="km" className={`block truncate text-xs ${done ? 'text-ink-soft' : 'text-ink-faint'}`}>{step.km}</span>
              <span className="tabular mt-0.5 block truncate text-xs text-ink-faint">{done && at(step.status) ? when(at(step.status)) : ' '}</span>
            </li>
          )
        })}
      </ol>
      {cancelled && (
        <p className="mt-3 flex items-center gap-2 text-[13px] font-medium text-madder-deep">
          <span aria-hidden className="h-2.5 w-6 rounded-[3px] bg-madder" />
          Cancelled{cut?.inserted_at ? ` · ${when(cut.inserted_at)}` : ''}
          {cut?.reason ? <span className="font-normal text-ink-soft">· {cut.reason}</span> : null}
        </p>
      )}
    </div>
  )
}

/** Compact weave for table rows: four short stripes and the status label. */
export function StatusTag({ status, en, km }: { status: string; en?: string; km?: string }) {
  const cancelled = status === 'cancelled'
  const filled = cancelled ? 0 : reached(status)
  return (
    <span className="inline-flex items-center gap-2.5 whitespace-nowrap">
      <span aria-hidden className="flex gap-[3px]">
        {STEPS.map((s, i) => (
          <span
            key={s.status}
            className={`h-3 w-1.5 rounded-[2px] ${cancelled ? 'bg-madder' : i < filled ? 'bg-clay' : 'bg-thread-strong/70'}`}
          />
        ))}
      </span>
      <span className={`text-[13px] font-medium ${cancelled ? 'text-madder-deep' : 'text-ink'}`}>
        {en ?? STEPS.find((s) => s.status === status)?.en ?? status}
        {km && <span lang="km" className="sr-only"> {km}</span>}
      </span>
    </span>
  )
}
