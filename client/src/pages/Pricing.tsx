import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'
import { MoreHorizontal, Plus } from 'lucide-react'
import { create, money, update, when, type Rec } from '#/lib/api'
import { apiKey, listQuery } from '#/lib/queries'
import { Bilingual, Button, Card, Err, Num, Page, Pill, Tray } from '#/components/kit'
import { FormField } from '#/components/form'
import { DataTable, type ColumnDef } from '#/components/data-table'
import { Input } from '@/components/ui/input'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

type Cat = { path: string; key: string; type: string; title: string; one: string; description: string; priceKey: 'price' | 'unit_price' }
const CATS: Cat[] = [
  {
    path: '/size-classes',
    key: 'size-classes',
    type: 'size-class',
    title: 'Size Classes',
    one: 'Size Class',
    description: 'Flat price per Parcel, used instead of weight.',
    priceKey: 'price',
  },
  {
    path: '/sale-items',
    key: 'sale-items',
    type: 'sale-item',
    title: 'Sale Items',
    one: 'Sale Item',
    description: 'Counter items sold with a Shipment.',
    priceKey: 'unit_price',
  },
]
const khr = (amount: string) => ({ amount, currency: 'KHR' })

const riel = z
  .string()
  .trim()
  .regex(/^\d+$/, 'Whole riel, digits only.')
  .refine((v) => Number(v) > 0, 'Must be more than 0.')

// ------------------------------------------------------------ price dialog

const priceSchema = z.object({ price: riel })

function PriceDialog({
  target,
  onClose,
  busy,
  error,
  onSave,
}: {
  target: { name: string; current: string } | null
  onClose: () => void
  busy: boolean
  error: unknown
  onSave: (price: string) => void
}) {
  const form = useForm({ resolver: zodResolver(priceSchema), defaultValues: { price: '' } })
  useEffect(() => {
    if (target) form.reset({ price: '' })
  }, [target, form])
  return (
    <Dialog open={!!target} onOpenChange={(o) => !o && !busy && onClose()}>
      <DialogContent className="sm:max-w-sm">
        <form noValidate onSubmit={form.handleSubmit((v) => onSave(v.price))} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>Change price</DialogTitle>
            <DialogDescription>
              {target?.name} is <span className="tabular">{target?.current}</span> now. Past Invoices keep their price.
            </DialogDescription>
          </DialogHeader>
          <FormField control={form.control} name="price" label="New price (៛)">
            {(f) => <Input {...f} autoFocus inputMode="numeric" autoComplete="off" className="tabular" />}
          </FormField>
          <Err error={error} />
          <DialogFooter>
            <Button variant="outline" disabled={busy} onClick={onClose}>
              Back
            </Button>
            <Button type="submit" busy={busy}>
              Save price
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

// --------------------------------------------------------------- catalogue

const itemSchema = z.object({
  name_en: z.string().trim().min(1, 'Enter the English name.'),
  name_km: z.string().trim().min(1, 'Enter the Khmer name.'),
  price: riel,
})

function Catalogue({ cat }: { cat: Cat }) {
  const qc = useQueryClient()
  const rowsQ = useQuery(listQuery(cat.path))
  const [editing, setEditing] = useState<Rec | null>(null)
  const refresh = () =>
    Promise.all([qc.invalidateQueries({ queryKey: apiKey(cat.key) }), qc.invalidateQueries({ queryKey: apiKey('price-changes') })])

  const form = useForm({ resolver: zodResolver(itemSchema), defaultValues: { name_en: '', name_km: '', price: '' } })
  const add = useMutation({
    mutationFn: (v: z.infer<typeof itemSchema>) => create(cat.path, cat.type, { name_en: v.name_en, name_km: v.name_km, [cat.priceKey]: khr(v.price) }),
    onSuccess: async (_d, v) => {
      toast.success(`${v.name_en} added`)
      form.reset()
      await refresh()
    },
  })
  const setPrice = useMutation({
    mutationFn: ({ id, price }: { id: string; price: string }) => update(`${cat.path}/${id}/price`, cat.type, { [cat.priceKey]: khr(price) }),
    onSuccess: async () => {
      toast.success(`Price updated for ${editing?.name_en ?? cat.one}`)
      setEditing(null)
      await refresh()
    },
  })
  const toggle = useMutation({
    mutationFn: (r: Rec) => update(`${cat.path}/${r.id}`, cat.type, { active: !r.active }),
    onSuccess: async (_d, r) => {
      toast.success(`${r.name_en} ${r.active ? 'deactivated' : 'activated'}`)
      await refresh()
    },
  })

  const columns = useMemo<ColumnDef<Rec>[]>(
    () => [
      {
        id: 'name',
        accessorFn: (r) => `${r.name_en} ${r.name_km ?? ''}`,
        header: 'Name',
        sortingFn: (a, b) => String(a.original.name_en).localeCompare(String(b.original.name_en)),
        cell: ({ row }) => (
          <span className={row.original.active ? '' : 'text-ink-faint'}>
            <Bilingual en={row.original.name_en} km={row.original.name_km} />
          </span>
        ),
      },
      {
        id: 'active',
        accessorFn: (r) => (r.active ? 'Active' : 'Inactive'),
        header: 'Status',
        cell: ({ row }) => (row.original.active ? <Pill tone="leaf">Active</Pill> : <Pill>Inactive</Pill>),
      },
      {
        id: 'price',
        accessorFn: (r) => Number(r[cat.priceKey]?.amount ?? 0),
        header: 'Price',
        meta: { align: 'right' },
        cell: ({ row }) => (
          <Num className={row.original.active ? 'font-medium' : 'text-ink-faint'}>{money(row.original[cat.priceKey])}</Num>
        ),
      },
      {
        id: 'actions',
        header: () => <span className="sr-only">Actions</span>,
        enableSorting: false,
        meta: { align: 'right', className: 'w-12' },
        cell: ({ row }) => {
          const r = row.original
          return (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon-sm" aria-label={`Actions for ${r.name_en}`} busy={toggle.isPending && toggle.variables?.id === r.id}>
                  <MoreHorizontal className="size-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-44">
                <DropdownMenuItem onSelect={() => setEditing(r)}>Change price…</DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem variant={r.active ? 'destructive' : 'default'} onSelect={() => toggle.mutate(r)}>
                  {r.active ? 'Deactivate' : 'Activate'}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )
        },
      },
    ],
    [cat.priceKey, toggle],
  )

  return (
    <Card title={cat.title} description={cat.description} flush>
      {toggle.error ? (
        <div className="px-5 pt-4">
          <Err error={toggle.error} />
        </div>
      ) : null}
      <DataTable
        id={`${cat.key}-table`}
        columns={columns}
        data={rowsQ.data}
        loading={rowsQ.isPending}
        empty={`No ${cat.title} yet. Add the first one below.`}
        search={{ placeholder: `Search ${cat.title}` }}
        initialSort={[{ id: 'name', desc: false }]}
        pageSize={10}
      />
      <Tray>
        <form
          noValidate
          className="grid items-start gap-3 sm:grid-cols-[1fr_1fr_140px_auto]"
          onSubmit={form.handleSubmit((v) => add.mutate(v))}
        >
          <FormField control={form.control} name="name_en" label="Name (English)">
            {(f) => <Input {...f} autoComplete="off" />}
          </FormField>
          <FormField control={form.control} name="name_km" label="Name (Khmer)">
            {(f) => <Input {...f} lang="km" autoComplete="off" />}
          </FormField>
          <FormField control={form.control} name="price" label="Price (៛)">
            {(f) => <Input {...f} inputMode="numeric" autoComplete="off" className="tabular" />}
          </FormField>
          <Button type="submit" variant="secondary" className="sm:mt-6" busy={add.isPending} icon={<Plus aria-hidden className="size-4" />}>
            Add {cat.one}
          </Button>
        </form>
        <Err error={add.error} />
      </Tray>
      <PriceDialog
        target={editing ? { name: editing.name_en, current: money(editing[cat.priceKey]) } : null}
        onClose={() => {
          setEditing(null)
          setPrice.reset()
        }}
        busy={setPrice.isPending}
        error={setPrice.error}
        onSave={(price) => editing && setPrice.mutate({ id: editing.id, price })}
      />
    </Card>
  )
}

// ----------------------------------------------------------------- page

const perKgSchema = z.object({ price: riel })
const feeSchema = z.object({
  percent: z
    .string()
    .trim()
    .regex(/^\d+(\.\d+)?$/, 'A number, e.g. 10 or 12.5.')
    .refine((v) => Number(v) >= 0 && Number(v) <= 100, 'Between 0 and 100.'),
  cap: riel,
})

const changeColumns: ColumnDef<Rec>[] = [
  {
    id: 'when',
    accessorFn: (c) => c.inserted_at,
    header: 'When',
    sortingFn: (a, b) => String(a.original.inserted_at).localeCompare(String(b.original.inserted_at)),
    cell: ({ row }) => <Num className="text-ink-soft">{when(row.original.inserted_at)}</Num>,
  },
  {
    id: 'kind',
    accessorFn: (c) => String(c.kind ?? '').replaceAll('_', ' '),
    header: 'Kind',
    cell: ({ getValue }) => <span className="capitalize">{getValue<string>()}</span>,
  },
  {
    id: 'price',
    accessorFn: (c) => Number(c.price?.amount ?? 0),
    header: 'New price',
    meta: { align: 'right' },
    cell: ({ row }) => <Num className="font-medium">{money(row.original.price)}</Num>,
  },
]

export function Pricing() {
  const qc = useQueryClient()
  const current = useQuery(listQuery('/pricing/current'))
  const changes = useQuery(listQuery('/price-changes'))
  const cur = current.data?.[0]
  const refresh = () =>
    Promise.all([qc.invalidateQueries({ queryKey: apiKey('pricing') }), qc.invalidateQueries({ queryKey: apiKey('price-changes') })])

  const perKgForm = useForm({ resolver: zodResolver(perKgSchema), defaultValues: { price: '' } })
  const feeForm = useForm({ resolver: zodResolver(feeSchema), defaultValues: { percent: '', cap: '' } })

  const savePerKg = useMutation({
    mutationFn: (v: z.infer<typeof perKgSchema>) => create('/pricing/price-per-kg', 'pricing-setting', { price_per_kg: khr(v.price) }),
    onSuccess: async () => {
      toast.success('Price per kg saved')
      perKgForm.reset()
      await refresh()
    },
  })
  const saveFee = useMutation({
    mutationFn: (v: z.infer<typeof feeSchema>) => create('/pricing/cancellation-fee', 'cancellation-fee-setting', { cap: khr(v.cap), percent: v.percent }),
    onSuccess: async (_d, v) => {
      toast.success(`Cancellation Fee set to ${v.percent}%, capped at ${Number(v.cap).toLocaleString('en-US')} ៛`)
      feeForm.reset()
      await refresh()
    },
  })

  return (
    <Page title="Pricing" subtitle="New prices apply to Shipments created from now on. Past Invoices keep their price.">
      <Err error={current.error} />
      <div className="grid gap-5 md:grid-cols-2">
        <Card title="Price per kg" description="Charged on Parcels sold by weight, rounded half-up to the riel.">
          <div>
            <p className="text-[13px] text-ink-soft">Current</p>
            <p className="tabular text-[28px] font-semibold tracking-[-0.015em]">
              {current.isPending ? (
                <span className="inline-block h-7 w-32 animate-pulse rounded bg-sunk align-middle" />
              ) : cur?.price_per_kg ? (
                money(cur.price_per_kg)
              ) : (
                'Not set'
              )}
            </p>
          </div>
          <form id="price-per-kg-form" noValidate className="flex items-start gap-2" onSubmit={perKgForm.handleSubmit((v) => savePerKg.mutate(v))}>
            <FormField control={perKgForm.control} name="price" label="New price (៛)" className="w-44">
              {(f) => <Input {...f} inputMode="numeric" autoComplete="off" className="tabular" />}
            </FormField>
            <Button type="submit" className="mt-6" busy={savePerKg.isPending}>
              Save
            </Button>
          </form>
          <Err error={savePerKg.error} />
        </Card>

        <Card title="Cancellation Fee" description="A percent of the Shipment Total, never more than the cap.">
          <form
            id="cancellation-fee-form"
            noValidate
            className="flex flex-wrap items-start gap-2"
            onSubmit={feeForm.handleSubmit((v) => saveFee.mutate(v))}
          >
            <FormField control={feeForm.control} name="percent" label="Percent" className="w-28">
              {(f) => <Input {...f} inputMode="decimal" autoComplete="off" className="tabular" />}
            </FormField>
            <FormField control={feeForm.control} name="cap" label="Cap (៛)" className="w-40">
              {(f) => <Input {...f} inputMode="numeric" autoComplete="off" className="tabular" />}
            </FormField>
            <Button type="submit" className="mt-6" busy={saveFee.isPending}>
              Save
            </Button>
          </form>
          <Err error={saveFee.error} />
        </Card>
      </div>

      {CATS.map((c) => (
        <Catalogue key={c.path} cat={c} />
      ))}

      <Card title="Price changes" description="Every change, newest first." flush>
        <DataTable
          id="price-changes-table"
          columns={changeColumns}
          data={changes.data}
          loading={changes.isPending}
          empty="No price changes yet."
          search={{ placeholder: 'Search by kind' }}
          initialSort={[{ id: 'when', desc: true }]}
          pageSize={10}
        />
      </Card>
    </Page>
  )
}
