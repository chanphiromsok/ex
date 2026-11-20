import { useEffect, useRef } from 'react'
import JsBarcode from 'jsbarcode'
import { useQuery } from '@tanstack/react-query'
import { money, when, type Rec } from '#/lib/api'
import { getSaleItemsOptions, getShipmentsByIdOptions, getSizeClassesOptions, getStationsOptions } from '#/api/@tanstack/react-query.gen'
import { asRow, asRows } from '#/lib/queries'
import { Card, Err } from '#/components/kit'
import { formatPhone } from '#/lib/phone'

const METHOD: Record<string, [string, string]> = {
  cash: ['Cash', 'សាច់ប្រាក់'],
  bank_transfer: ['Bank transfer', 'ផ្ទេរប្រាក់តាមធនាគារ'],
  qr: ['QR', 'QR'],
}

/** Code 128 barcode of the Invoice Number, so a scanner can type it into a Manifest or the Shipments search. */
function Barcode({ value }: { value: string }) {
  const ref = useRef<SVGSVGElement>(null)
  useEffect(() => {
    if (ref.current)
      JsBarcode(ref.current, value, { format: 'CODE128', displayValue: false, height: 44, width: 2, margin: 0, lineColor: '#000' })
  }, [value])
  return <svg ref={ref} role="img" aria-label={`Barcode of Invoice Number ${value}`} className="mx-auto max-w-full" />
}

function Line({ en, km, children, strong }: { en: string; km: string; children: React.ReactNode; strong?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-1">
      <span className="text-xs text-ink-soft">
        {en} <span lang="km">· {km}</span>
      </span>
      <span className={`tabular text-right text-sm ${strong ? 'font-semibold' : 'font-medium'}`}>{children}</span>
    </div>
  )
}

/**
 * The printable Invoice for one Shipment. Give it the Shipment loaded with
 * `include=parcels,sale_items,payments`, plus the lists used to name Stations, Size Classes and Sale Items.
 * Only this block prints: the rest of the page is hidden by the `.invoice-print` rules in styles.css.
 */
export function Invoice({
  shipment: s,
  stations,
  sizeClasses,
  saleItems,
}: {
  shipment: Rec
  stations?: Rec[]
  sizeClasses?: Rec[]
  saleItems?: Rec[]
}) {
  const station = (id: string) => stations?.find((x) => x.id === id)
  const from = station(s.origin_station_id)
  const to = station(s.destination_station_id)
  const sizeName = (id: string) => sizeClasses?.find((x) => x.id === id)?.name_en ?? 'By size'
  const itemName = (id: string) => saleItems?.find((x) => x.id === id)?.name_en ?? 'Sale Item'
  const payments: Rec[] = (s.payments ?? []).filter((p: Rec) => p.kind !== 'refund')
  const method = METHOD[payments[0]?.method]
  const parcels: Rec[] = s.parcels ?? []
  const items: Rec[] = s.sale_items ?? []

  return (
    <article id="invoice" className="invoice-print mx-auto w-full max-w-[420px] rounded-weave border border-thread bg-white p-5 text-ink">
      <header className="text-center">
        <p className="text-sm font-semibold tracking-wide">Express Cargo</p>
        <p className="text-xs text-ink-soft">
          Invoice <span lang="km">· វិក្កយប័ត្រ</span>
        </p>
        <p id="invoice-no" className="tabular mt-2 text-[40px] leading-none font-semibold tracking-[-0.02em]">
          #{s.invoice_no}
        </p>
        <p className="tabular mt-1 text-xs text-ink-soft">{when(s.inserted_at)}</p>
      </header>

      <div className="mt-4 border-t border-dashed border-thread pt-2">
        <Line en="From" km="ពី">
          {from ? <>{from.name_en} <span lang="km" className="text-ink-soft">{from.name_km}</span></> : '—'}
        </Line>
        <Line en="To" km="ទៅ">
          {to ? <>{to.name_en} <span lang="km" className="text-ink-soft">{to.name_km}</span></> : '—'}
        </Line>
        <Line en="Sender" km="អ្នកផ្ញើ">{formatPhone(s.sender_phone)}</Line>
        <Line en="Receiver" km="អ្នកទទួល">{formatPhone(s.receiver_phone)}</Line>
      </div>

      <div className="mt-2 border-t border-dashed border-thread pt-2">
        {parcels.map((p, i) => (
          <Line key={p.id ?? i} en={`Parcel ${i + 1}`} km={`ឥវ៉ាន់ ${i + 1}`}>
            {p.measurement_type === 'kg' ? `${p.weight_kg} kg` : sizeName(p.size_class_id)} · {money(p.chargeable_amount)}
          </Line>
        ))}
        {items.map((it, i) => (
          <Line key={it.id ?? i} en={`${itemName(it.sale_item_id)} × ${it.quantity}`} km="ទំនិញលក់">
            {money({ amount: String(Number(it.unit_price?.amount ?? 0) * Number(it.quantity ?? 0)), currency: it.unit_price?.currency ?? 'KHR' })}
          </Line>
        ))}
      </div>

      <div className="mt-2 border-t border-dashed border-thread pt-2">
        <Line en="Total" km="សរុប" strong>
          <span id="invoice-total">{money(s.shipment_total)}</span>
        </Line>
        {method && (
          <Line en="Paid by" km="បង់ដោយ">
            {method[0]} <span lang="km">{method[1]}</span>
          </Line>
        )}
        {s.declared_value && (
          <Line en="Declared value" km="តម្លៃប្រកាស">{money(s.declared_value)}</Line>
        )}
      </div>

      <footer className="mt-4 border-t border-dashed border-thread pt-4 text-center">
        <Barcode value={String(s.invoice_no)} />
        <p className="tabular mt-1 text-xs text-ink-soft">{s.invoice_no}</p>
        <p className="mt-3 text-xs text-ink-soft">
          Keep this Invoice to collect the Shipment. <span lang="km">សូមរក្សាវិក្កយប័ត្រនេះដើម្បីទទួលឥវ៉ាន់។</span>
        </p>
      </footer>
    </article>
  )
}

/** Loads one Shipment with what the Invoice needs and shows it. */
export function InvoiceLoader({ id }: { id: string }) {
  const shipment = useQuery({ ...getShipmentsByIdOptions({ path: { id }, query: { include: 'parcels,sale_items,payments' } }), select: asRow })
  const stations = useQuery({ ...getStationsOptions(), select: asRows })
  const sizeClasses = useQuery({ ...getSizeClassesOptions(), select: asRows })
  const saleItems = useQuery({ ...getSaleItemsOptions(), select: asRows })
  if (!shipment.data)
    return shipment.isPending ? (
      <Card>
        <div className="h-48 animate-pulse rounded bg-sunk" />
      </Card>
    ) : (
      <Err error={shipment.error} />
    )
  return <Invoice shipment={shipment.data} stations={stations.data} sizeClasses={sizeClasses.data} saleItems={saleItems.data} />
}
