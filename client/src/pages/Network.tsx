import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useForm, useWatch } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'
import { ArrowRight, MoreHorizontal, Plus, Trash2 } from 'lucide-react'
import { create, remove, update, type Rec } from '#/lib/api'
import { getLocationsOptions, getRoutesOptions, getStationsOptions } from '#/api/@tanstack/react-query.gen'
import { asRows, resource } from '#/lib/queries'
import { Bilingual, Button, Card, Err, Page, Pill, Tray } from '#/components/kit'
import { Combobox, FormField, type Option } from '#/components/form'
import { DataTable, type ColumnDef } from '#/components/data-table'
import { ConfirmDialog } from '#/components/confirm-dialog'
import { Input } from '@/components/ui/input'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'

const named = {
  name_en: z.string().trim().min(1, 'Enter the English name.'),
  name_km: z.string().trim().min(1, 'Enter the Khmer name.'),
}
const locationSchema = z.object(named)
const stationSchema = z.object({ location_id: z.string().min(1, 'Choose a Location.'), ...named, external_id: z.string().trim() })
const routeSchema = z
  .object({
    origin: z.string().min(1, 'Choose where it starts.'),
    destination: z.string().min(1, 'Choose where it ends.'),
  })
  .refine((v) => v.origin !== v.destination, { path: ['destination'], message: 'Pick a different Location.' })

type Pending = { kind: 'location' | 'route'; id: string; label: string } | null

const byName = (a: { original: Rec }, b: { original: Rec }) => String(a.original.name_en).localeCompare(String(b.original.name_en))

export function Network() {
  const qc = useQueryClient()
  const locationsQ = useQuery({ ...getLocationsOptions(), select: asRows })
  const stationsQ = useQuery({ ...getStationsOptions(), select: asRows })
  const routesQ = useQuery({ ...getRoutesOptions(), select: asRows })
  const locations = locationsQ.data ?? []
  const name = (id: string) => locations.find((l) => l.id === id)?.name_en ?? '—'
  const options: Option[] = locations.map((l) => ({ value: l.id, label: l.name_en, hint: l.name_km, keywords: [l.name_km ?? ''] }))
  const refresh = (...keys: string[]) => Promise.all(keys.map((k) => qc.invalidateQueries(resource(k))))

  const locForm = useForm({ resolver: zodResolver(locationSchema), defaultValues: { name_en: '', name_km: '' } })
  const stForm = useForm({ resolver: zodResolver(stationSchema), defaultValues: { location_id: '', name_en: '', name_km: '', external_id: '' } })
  const rtForm = useForm({ resolver: zodResolver(routeSchema), defaultValues: { origin: '', destination: '' } })
  const origin = useWatch({ control: rtForm.control, name: 'origin' })

  const [pending, setPending] = useState<Pending>(null)

  const addLoc = useMutation({
    mutationFn: (v: z.infer<typeof locationSchema>) => create('/locations', 'location', v),
    onSuccess: async (_d, v) => {
      toast.success(`${v.name_en} added`)
      locForm.reset()
      await refresh('locations')
    },
  })
  const addSt = useMutation({
    mutationFn: (v: z.infer<typeof stationSchema>) => create('/stations', 'station', { ...v, external_id: v.external_id || undefined }),
    onSuccess: async (_d, v) => {
      toast.success(`${v.name_en} Station added`)
      stForm.reset()
      await refresh('stations')
    },
  })
  const toggleSt = useMutation({
    mutationFn: (s: Rec) => update(`/stations/${s.id}`, 'station', { active: !s.active }),
    onSuccess: async (_d, s) => {
      toast.success(`${s.name_en} ${s.active ? 'deactivated' : 'activated'}`)
      await refresh('stations')
    },
  })
  const addRt = useMutation({
    mutationFn: (v: z.infer<typeof routeSchema>) =>
      create('/routes', 'route', { origin_location_id: v.origin, destination_location_id: v.destination }),
    onSuccess: async (_d, v) => {
      toast.success(`Route ${name(v.origin)} → ${name(v.destination)} added`)
      rtForm.reset()
      await refresh('routes')
    },
  })
  const del = useMutation({
    mutationFn: (p: NonNullable<Pending>) => remove(p.kind === 'location' ? `/locations/${p.id}` : `/routes/${p.id}`),
    onSuccess: async (_d, p) => {
      toast.success(`${p.label} deleted`)
      setPending(null)
      await refresh(...(p.kind === 'location' ? ['locations', 'routes'] : ['routes']))
    },
  })
  const askDelete = (p: NonNullable<Pending>) => {
    del.reset()
    setPending(p)
  }

  const stationColumns = useMemo<ColumnDef<Rec>[]>(
    () => [
      {
        id: 'name',
        accessorFn: (s) => `${s.name_en} ${s.name_km ?? ''}`,
        header: 'Station',
        sortingFn: byName,
        cell: ({ row }) => (
          <span className={row.original.active ? '' : 'text-ink-faint'}>
            <Bilingual en={row.original.name_en} km={row.original.name_km} />
          </span>
        ),
      },
      {
        id: 'location',
        accessorFn: (s) => name(s.location_id),
        header: 'Location',
        cell: ({ getValue }) => <span className="text-ink-soft">{getValue<string>()}</span>,
      },
      {
        id: 'external_id',
        accessorFn: (s) => s.external_id ?? '',
        header: 'Schedule ID',
        cell: ({ getValue }) => <span className="font-mono text-xs text-ink-soft">{getValue<string>() || '—'}</span>,
      },
      {
        id: 'active',
        accessorFn: (s) => (s.active ? 'Active' : 'Inactive'),
        header: 'Status',
        cell: ({ row }) => (row.original.active ? <Pill tone="leaf">Active</Pill> : <Pill>Inactive</Pill>),
      },
      {
        id: 'actions',
        header: () => <span className="sr-only">Actions</span>,
        enableSorting: false,
        meta: { align: 'right', className: 'w-12' },
        cell: ({ row }) => {
          const s = row.original
          return (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon-sm" aria-label={`Actions for ${s.name_en}`} disabled={toggleSt.isPending && toggleSt.variables?.id === s.id}>
                  <MoreHorizontal className="size-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-40">
                <DropdownMenuItem variant={s.active ? 'destructive' : 'default'} onSelect={() => toggleSt.mutate(s)}>
                  {s.active ? 'Deactivate' : 'Activate'}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )
        },
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [locations, toggleSt.isPending, toggleSt.variables],
  )

  const deleteCell = (label: string, p: NonNullable<Pending>) => (
    <Button variant="ghost" size="icon-sm" aria-label={label} title={label} onClick={() => askDelete(p)}>
      <Trash2 aria-hidden className="size-4" />
    </Button>
  )

  const locationColumns = useMemo<ColumnDef<Rec>[]>(
    () => [
      {
        id: 'name',
        accessorFn: (l) => `${l.name_en} ${l.name_km ?? ''}`,
        header: 'Location',
        sortingFn: byName,
        cell: ({ row }) => <Bilingual en={row.original.name_en} km={row.original.name_km} />,
      },
      {
        id: 'actions',
        header: () => <span className="sr-only">Actions</span>,
        enableSorting: false,
        meta: { align: 'right', className: 'w-12' },
        cell: ({ row }) => deleteCell(`Delete ${row.original.name_en}`, { kind: 'location', id: row.original.id, label: row.original.name_en }),
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  )

  const routeColumns = useMemo<ColumnDef<Rec>[]>(
    () => [
      { id: 'from', accessorFn: (r) => name(r.origin_location_id), header: 'From' },
      {
        id: 'to',
        accessorFn: (r) => name(r.destination_location_id),
        header: 'To',
        cell: ({ getValue }) => (
          <span className="inline-flex items-center gap-2">
            <ArrowRight aria-hidden className="size-3.5 text-ink-faint" />
            {getValue<string>()}
          </span>
        ),
      },
      {
        id: 'actions',
        header: () => <span className="sr-only">Actions</span>,
        enableSorting: false,
        meta: { align: 'right', className: 'w-12' },
        cell: ({ row }) => {
          const label = `${name(row.original.origin_location_id)} → ${name(row.original.destination_location_id)}`
          return deleteCell(`Delete route ${label}`, { kind: 'route', id: row.original.id, label: `Route ${label}` })
        },
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [locations],
  )

  return (
    <Page title="Stations & routes" subtitle="Locations are places; Stations are counters at a Location; Routes connect Locations.">
      <Err error={locationsQ.error ?? stationsQ.error ?? routesQ.error} />

      <Card title="Stations" description="Inactive Stations can't be picked as a destination." flush>
        {toggleSt.error ? (
          <div className="px-5 pt-4">
            <Err error={toggleSt.error} />
          </div>
        ) : null}
        <DataTable
          id="stations-table"
          columns={stationColumns}
          data={stationsQ.data}
          loading={stationsQ.isPending}
          empty="No Stations yet. Add the first one below."
          search={{ placeholder: 'Search Stations or Locations' }}
          initialSort={[{ id: 'name', desc: false }]}
          pageSize={10}
        />
        <Tray>
          <form
            id="station-form"
            noValidate
            className="grid items-start gap-3 sm:grid-cols-[1fr_1fr_1fr_auto]"
            onSubmit={stForm.handleSubmit((v) => addSt.mutate(v))}
          >
            <FormField control={stForm.control} name="location_id" label="Location">
              {(f, s) => (
                <Combobox
                  id={f.id}
                  value={f.value}
                  onChange={f.onChange}
                  options={options}
                  invalid={!!s.error}
                  placeholder="Choose a Location"
                  searchPlaceholder="Search Locations"
                />
              )}
            </FormField>
            <FormField control={stForm.control} name="name_en" label="Name (English)">
              {(f) => <Input {...f} autoComplete="off" />}
            </FormField>
            <FormField control={stForm.control} name="name_km" label="Name (Khmer)">
              {(f) => <Input {...f} lang="km" autoComplete="off" />}
            </FormField>
            <FormField control={stForm.control} name="external_id" label="Schedule ID (optional)">
              {(f) => <Input {...f} autoComplete="off" className="font-mono" />}
            </FormField>
            <Button type="submit" variant="secondary" className="sm:mt-6" busy={addSt.isPending} icon={<Plus aria-hidden className="size-4" />}>
              Add Station
            </Button>
          </form>
          <Err error={addSt.error} />
        </Tray>
      </Card>

      <div className="grid items-start gap-5 lg:grid-cols-2">
        <Card title="Locations" description="A Location can only be deleted once no Station or Route uses it." flush>
          <DataTable
            id="locations-table"
            columns={locationColumns}
            data={locationsQ.data}
            loading={locationsQ.isPending}
            empty="No Locations yet."
            search={{ placeholder: 'Search Locations' }}
            initialSort={[{ id: 'name', desc: false }]}
            pageSize={8}
          />
          <Tray>
            <form
              id="location-form"
              noValidate
              className="grid items-start gap-3 sm:grid-cols-[1fr_1fr_auto]"
              onSubmit={locForm.handleSubmit((v) => addLoc.mutate(v))}
            >
              <FormField control={locForm.control} name="name_en" label="English">
                {(f) => <Input {...f} autoComplete="off" />}
              </FormField>
              <FormField control={locForm.control} name="name_km" label="Khmer">
                {(f) => <Input {...f} lang="km" autoComplete="off" />}
              </FormField>
              <Button type="submit" variant="secondary" className="sm:mt-6" busy={addLoc.isPending} icon={<Plus aria-hidden className="size-4" />}>
                Add
              </Button>
            </form>
            <Err error={addLoc.error} />
          </Tray>
        </Card>

        <Card title="Routes" description="Each Route runs one direction. Add the return trip separately." flush>
          <DataTable
            id="routes-table"
            columns={routeColumns}
            data={routesQ.data}
            loading={routesQ.isPending}
            empty="No Routes yet."
            search={{ placeholder: 'Search Routes' }}
            initialSort={[{ id: 'from', desc: false }]}
            pageSize={8}
          />
          <Tray>
            <form
              id="route-form"
              noValidate
              className="grid items-start gap-3 sm:grid-cols-[1fr_1fr_auto]"
              onSubmit={rtForm.handleSubmit((v) => addRt.mutate(v))}
            >
              <FormField control={rtForm.control} name="origin" label="From">
                {(f, s) => (
                  <Combobox id={f.id} value={f.value} onChange={f.onChange} options={options} invalid={!!s.error} searchPlaceholder="Search Locations" />
                )}
              </FormField>
              <FormField control={rtForm.control} name="destination" label="To">
                {(f, s) => (
                  <Combobox
                    id={f.id}
                    value={f.value}
                    onChange={f.onChange}
                    options={options.filter((o) => o.value !== origin)}
                    invalid={!!s.error}
                    searchPlaceholder="Search Locations"
                  />
                )}
              </FormField>
              <Button type="submit" variant="secondary" className="sm:mt-6" busy={addRt.isPending} icon={<Plus aria-hidden className="size-4" />}>
                Add
              </Button>
            </form>
            <Err error={addRt.error} />
          </Tray>
        </Card>
      </div>

      <ConfirmDialog
        open={!!pending}
        onOpenChange={(o) => !o && setPending(null)}
        title={`Delete ${pending?.label ?? ''}?`}
        description={
          pending?.kind === 'location'
            ? 'This only works if no Station or Route uses it. This can’t be undone.'
            : 'Shipments already on this Route are not affected. This can’t be undone.'
        }
        confirm="Delete"
        busy={del.isPending}
        error={del.error}
        onConfirm={() => pending && del.mutate(pending)}
      />
    </Page>
  )
}
