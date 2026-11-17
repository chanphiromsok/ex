import { createFileRoute } from '@tanstack/react-router'
import { Printer } from 'lucide-react'
import { Button, Page } from '#/components/kit'
import { InvoiceLoader } from '#/components/invoice'

// Reprint of a Shipment's Invoice, for a Sender who lost theirs. Guarded by the /shipments layout.
export const Route = createFileRoute('/_app/shipments/$id/invoice')({ component: Screen })

function Screen() {
  const { id } = Route.useParams()
  const navigate = Route.useNavigate()
  return (
    <Page
      title="Invoice"
      onBack={() => navigate({ to: '/shipments/$id', params: { id } })}
      backLabel="Shipment"
      action={
        <Button id="print-invoice" icon={<Printer aria-hidden className="size-4" />} onClick={() => window.print()}>
          Print Invoice
        </Button>
      }
    >
      <InvoiceLoader id={id} />
    </Page>
  )
}
