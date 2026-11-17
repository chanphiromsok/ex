import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useForm, useWatch } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { toast } from 'sonner'
import { Pencil, UserPlus } from 'lucide-react'
import { create, update, type Rec } from '#/lib/api'
import { apiKey, listQuery } from '#/lib/queries'
import { Bilingual, Button, Card, Err, Num, Page, Tray } from '#/components/kit'
import { Choice, Combobox, FormField, Segmented, type Option } from '#/components/form'
import { DataTable, type ColumnDef } from '#/components/data-table'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'

const ROLES: Option[] = [
  { value: 'staff', label: 'Staff' },
  { value: 'supervisor', label: 'Supervisor' },
  { value: 'admin', label: 'Admin' },
]
const roleLabel = (v: string) => ROLES.find((r) => r.value === v)?.label ?? v
const days = (n: number) => `${n} ${n === 1 ? 'day' : 'days'}`
const byName = (a: { original: Rec }, b: { original: Rec }) => String(a.original.name_en).localeCompare(String(b.original.name_en))

// ------------------------------------------------------ station settings

const thresholdSchema = z.object({
  days: z
    .string()
    .trim()
    .regex(/^\d+$/, 'Whole days, digits only.')
    .refine((v) => Number(v) >= 1 && Number(v) <= 90, 'Between 1 and 90 days.'),
})

function ThresholdDialog({ station, onClose }: { station: Rec | null; onClose: () => void }) {
  const qc = useQueryClient()
  const form = useForm({ resolver: zodResolver(thresholdSchema), defaultValues: { days: '' } })
  const save = useMutation({
    mutationFn: (v: z.infer<typeof thresholdSchema>) =>
      update(`/stations/${station!.id}/overdue-threshold`, 'station', { overdue_threshold_days: Number(v.days) }),
    onSuccess: async (_d, v) => {
      toast.success(`${station?.name_en}: Overdue after ${days(Number(v.days))}`)
      await qc.invalidateQueries({ queryKey: apiKey('stations') })
      onClose()
    },
  })
  useEffect(() => {
    if (station) {
      form.reset({ days: String(station.overdue_threshold_days ?? '') })
      save.reset()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [station])

  return (
    <Dialog open={!!station} onOpenChange={(o) => !o && !save.isPending && onClose()}>
      <DialogContent className="sm:max-w-sm">
        <form noValidate className="grid gap-4" onSubmit={form.handleSubmit((v) => save.mutate(v))}>
          <DialogHeader>
            <DialogTitle>Overdue threshold</DialogTitle>
            <DialogDescription>
              A Shipment at {station?.name_en} becomes Overdue when it has waited this many days after arriving.
            </DialogDescription>
          </DialogHeader>
          <FormField control={form.control} name="days" id="overdue-days" label="Days (1–90)">
            {(f) => <Input {...f} autoFocus inputMode="numeric" autoComplete="off" className="tabular" />}
          </FormField>
          <Err error={save.error} />
          <DialogFooter>
            <Button variant="outline" disabled={save.isPending} onClick={onClose}>
              Back
            </Button>
            <Button type="submit" busy={save.isPending}>
              Save
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export function StationSettings() {
  const qc = useQueryClient()
  const stationsQ = useQuery(listQuery('/stations'))
  const [editing, setEditing] = useState<Rec | null>(null)

  const approval = useMutation({
    mutationFn: (s: Rec) =>
      update(`/stations/${s.id}/cancellation-approval`, 'station', { cancellation_requires_approval: !s.cancellation_requires_approval }),
    onSuccess: async (_d, s) => {
      toast.success(
        s.cancellation_requires_approval
          ? `${s.name_en}: Cancellations go through straight away`
          : `${s.name_en}: Cancellations now need a Supervisor`,
      )
      await qc.invalidateQueries({ queryKey: apiKey('stations') })
    },
  })

  const columns = useMemo<ColumnDef<Rec>[]>(
    () => [
      {
        id: 'name',
        accessorFn: (s) => `${s.name_en} ${s.name_km ?? ''}`,
        header: 'Station',
        sortingFn: byName,
        cell: ({ row }) => <Bilingual en={row.original.name_en} km={row.original.name_km} />,
      },
      {
        id: 'approval',
        accessorFn: (s) => (s.cancellation_requires_approval ? 'Supervisor approves' : 'Cancels straight away'),
        header: 'Cancellation',
        cell: ({ row }) => {
          const s = row.original
          const on = !!s.cancellation_requires_approval
          return (
            <label className="inline-flex cursor-pointer items-center gap-2.5">
              <Switch
                id={`approval-${s.id}`}
                checked={on}
                disabled={approval.isPending && approval.variables?.id === s.id}
                onCheckedChange={() => approval.mutate(s)}
                aria-label={`${s.name_en}: Cancellation needs approval`}
              />
              <span className="text-[13px] text-ink-soft">{on ? 'Supervisor approves' : 'Cancels straight away'}</span>
            </label>
          )
        },
      },
      {
        id: 'threshold',
        accessorFn: (s) => Number(s.overdue_threshold_days ?? 0),
        header: 'Overdue after',
        meta: { align: 'right' },
        cell: ({ row }) => (
          <span className="inline-flex items-center gap-1">
            <Num className="font-medium">{days(row.original.overdue_threshold_days)}</Num>
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label={`Change Overdue threshold for ${row.original.name_en}`}
              title="Change"
              onClick={() => setEditing(row.original)}
            >
              <Pencil aria-hidden className="size-3.5" />
            </Button>
          </span>
        ),
      },
    ],
    [approval],
  )

  return (
    <Page title="Station settings" subtitle="Per-Station rules for Cancellations and Overdue Shipments.">
      <Err error={stationsQ.error ?? approval.error} />
      <Card flush>
        <DataTable
          id="station-settings-table"
          columns={columns}
          data={stationsQ.data}
          loading={stationsQ.isPending}
          empty="No Stations yet. Add them under Stations & routes."
          search={{ placeholder: 'Search Stations' }}
          initialSort={[{ id: 'name', desc: false }]}
        />
      </Card>
      <ThresholdDialog station={editing} onClose={() => setEditing(null)} />
    </Page>
  )
}

// ----------------------------------------------------------------- users

const NO_STATION = 'none'

const userSchema = z
  .object({
    email: z.string().trim().min(1, 'Enter an email.').email('Enter a valid email.'),
    password: z.string().min(8, 'At least 8 characters.'),
    role: z.enum(['staff', 'supervisor', 'admin']),
    station_id: z.string(),
  })
  .refine((v) => v.role === 'admin' || !!v.station_id, { path: ['station_id'], message: 'Staff and Supervisors need a Station.' })

const blankUser: z.input<typeof userSchema> = { email: '', password: '', role: 'staff', station_id: '' }

export function Users() {
  const qc = useQueryClient()
  const usersQ = useQuery(listQuery('/users'))
  const stationsQ = useQuery(listQuery('/stations'))
  const stations = stationsQ.data ?? []
  const stationOptions: Option[] = stations.map((s) => ({ value: s.id, label: s.name_en, hint: s.name_km, keywords: [s.name_km ?? ''] }))
  const stationName = (id?: string | null) => stations.find((s) => s.id === id)?.name_en ?? ''
  const [roleFilter, setRoleFilter] = useState('all')
  const refresh = () => qc.invalidateQueries({ queryKey: apiKey('users') })

  const form = useForm({ resolver: zodResolver(userSchema), defaultValues: blankUser })
  const role = useWatch({ control: form.control, name: 'role' })
  useEffect(() => {
    if (role === 'admin') form.setValue('station_id', '', { shouldValidate: false })
  }, [role, form])

  const add = useMutation({
    mutationFn: (v: z.infer<typeof userSchema>) =>
      create('/users', 'user', {
        email: v.email,
        password: v.password,
        password_confirmation: v.password,
        role: v.role,
        station_id: v.role === 'admin' ? null : v.station_id,
      }),
    onSuccess: async (_d, v) => {
      toast.success(`${v.email} can sign in now`)
      form.reset(blankUser)
      await refresh()
    },
  })
  const change = useMutation({
    mutationFn: ({ u, attrs }: { u: Rec; attrs: Record<string, unknown>; what: string }) => update(`/users/${u.id}`, 'user', attrs),
    onSuccess: async (_d, { u, what }) => {
      toast.success(`${u.email}: ${what}`)
      await refresh()
    },
    onError: (e, { u }) => toast.error(`Couldn't update ${u.email}`, { description: e instanceof Error ? e.message : String(e) }),
  })

  const rows = useMemo(() => (usersQ.data ?? []).filter((u) => roleFilter === 'all' || u.role === roleFilter), [usersQ.data, roleFilter])

  const columns = useMemo<ColumnDef<Rec>[]>(
    () => [
      {
        id: 'email',
        accessorFn: (u) => u.email,
        header: 'Email',
        cell: ({ getValue }) => <span className="font-medium">{getValue<string>()}</span>,
      },
      {
        id: 'role',
        accessorFn: (u) => roleLabel(u.role),
        header: 'Role',
        cell: ({ row }) => {
          const u = row.original
          return (
            <Choice
              id={`role-${u.id}`}
              size="sm"
              className="w-36"
              aria-label={`Role for ${u.email}`}
              value={u.role}
              options={ROLES}
              disabled={change.isPending && change.variables?.u.id === u.id}
              onChange={(v) => v !== u.role && change.mutate({ u, attrs: { role: v }, what: `now ${roleLabel(v)}` })}
            />
          )
        },
      },
      {
        id: 'station',
        accessorFn: (u) => stationName(u.station_id),
        header: 'Station',
        cell: ({ row }) => {
          const u = row.original
          return (
            <Combobox
              id={`station-${u.id}`}
              className="h-8 w-48"
              aria-label={`Station for ${u.email}`}
              value={u.station_id ?? NO_STATION}
              options={[{ value: NO_STATION, label: 'No Station' }, ...stationOptions]}
              searchPlaceholder="Search Stations"
              disabled={change.isPending && change.variables?.u.id === u.id}
              onChange={(v) => {
                const next = v === NO_STATION ? null : v
                if (next === (u.station_id ?? null)) return
                change.mutate({ u, attrs: { station_id: next }, what: next ? `moved to ${stationName(next)}` : 'no Station' })
              }}
            />
          )
        },
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [stations, change.isPending, change.variables],
  )

  return (
    <Page title="Users" subtitle="Role decides what each person can do. Staff and Supervisors work at one Station.">
      <Err error={usersQ.error} />
      <Card flush>
        <DataTable
          id="users-table"
          columns={columns}
          data={rows}
          loading={usersQ.isPending}
          empty={roleFilter === 'all' ? 'No users yet.' : `No ${roleLabel(roleFilter)} users.`}
          search={{ placeholder: 'Search by email or Station' }}
          toolbar={
            <Segmented
              aria-label="Filter by role"
              value={roleFilter}
              onChange={setRoleFilter}
              options={[{ value: 'all', label: 'All' }, ...ROLES]}
            />
          }
          initialSort={[{ id: 'email', desc: false }]}
        />
        <Tray>
          <p className="mb-3 text-[13px] font-semibold">New user</p>
          <form
            id="user-form"
            noValidate
            className="grid items-start gap-3 sm:grid-cols-2 lg:grid-cols-[1.4fr_1fr_150px_1fr_auto]"
            onSubmit={form.handleSubmit((v) => add.mutate(v))}
          >
            <FormField control={form.control} name="email" id="new-user-email" label="Email">
              {(f) => <Input {...f} type="email" autoComplete="off" />}
            </FormField>
            <FormField control={form.control} name="password" id="new-user-password" label="Password" description="At least 8 characters.">
              {(f) => <Input {...f} type="password" autoComplete="new-password" />}
            </FormField>
            <FormField control={form.control} name="role" id="new-user-role" label="Role">
              {(f) => <Choice id={f.id} value={f.value} onChange={f.onChange} options={ROLES} />}
            </FormField>
            <FormField control={form.control} name="station_id" id="new-user-station" label="Station">
              {(f, s) => (
                <Combobox
                  id={f.id}
                  value={f.value}
                  onChange={f.onChange}
                  options={stationOptions}
                  invalid={!!s.error}
                  disabled={role === 'admin'}
                  placeholder={role === 'admin' ? 'Admins have none' : 'Choose a Station'}
                  searchPlaceholder="Search Stations"
                />
              )}
            </FormField>
            <Button type="submit" className="lg:mt-6" busy={add.isPending} icon={<UserPlus aria-hidden className="size-4" />}>
              Create
            </Button>
          </form>
          <Err error={add.error} />
        </Tray>
      </Card>
    </Page>
  )
}
