import { useId, useState, type ReactNode } from 'react'
import {
  Controller,
  type Control,
  type ControllerFieldState,
  type ControllerRenderProps,
  type FieldPath,
  type FieldValues,
} from 'react-hook-form'
import { CalendarDays, Check, ChevronsUpDown } from 'lucide-react'
import type { DateRange } from 'react-day-picker'
import { Field, FieldDescription, FieldError, FieldLabel } from '@/components/ui/field'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group'
import { dayjs, fmtDay, ppDay } from '#/lib/date'
import { cn } from '@/lib/utils'

/**
 * One react-hook-form field: label, control, hint and the validation message.
 * `children` gets the Controller field plus the id to put on the control.
 */
export function FormField<T extends FieldValues, N extends FieldPath<T>>({
  control,
  name,
  label,
  description,
  id,
  className,
  children,
}: {
  control: Control<T>
  name: N
  label: ReactNode
  description?: ReactNode
  id?: string
  className?: string
  children: (field: ControllerRenderProps<T, N> & { id: string; 'aria-invalid': boolean }, state: ControllerFieldState) => ReactNode
}) {
  const auto = useId()
  const controlId = id ?? `${String(name)}-${auto}`
  return (
    <Controller
      control={control}
      name={name}
      render={({ field, fieldState }) => (
        <Field data-invalid={fieldState.invalid || undefined} className={cn('gap-1.5', className)}>
          <FieldLabel htmlFor={controlId} className="text-[13px] text-ink-soft">
            {label}
          </FieldLabel>
          {children({ ...field, id: controlId, 'aria-invalid': fieldState.invalid }, fieldState)}
          {description && !fieldState.invalid && <FieldDescription className="text-xs">{description}</FieldDescription>}
          {fieldState.invalid && <FieldError className="text-xs" errors={[fieldState.error]} />}
        </Field>
      )}
    />
  )
}

export type Option = { value: string; label: string; hint?: string; keywords?: string[] }

/** A short fixed list: shadcn Select. Radix can't hold '' as a value, so '' shows the placeholder. */
export function Choice({
  id,
  value,
  onChange,
  options,
  placeholder = 'Choose…',
  size = 'default',
  disabled,
  invalid,
  className,
  'aria-label': ariaLabel,
}: {
  id?: string
  value: string
  onChange: (v: string) => void
  options: Option[]
  placeholder?: string
  size?: 'sm' | 'default'
  disabled?: boolean
  invalid?: boolean
  className?: string
  'aria-label'?: string
}) {
  return (
    <Select value={value || undefined} onValueChange={onChange} disabled={disabled}>
      <SelectTrigger id={id} size={size} aria-invalid={invalid || undefined} aria-label={ariaLabel} className={cn('w-full', className)}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent position="popper" className="max-h-72">
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
            {o.hint && <span className="ml-auto pl-3 text-xs text-ink-faint">{o.hint}</span>}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

/** A searchable dropdown for longer lists (Stations, Locations, Size Classes). */
export function Combobox({
  id,
  value,
  onChange,
  options,
  placeholder = 'Choose…',
  searchPlaceholder = 'Search…',
  empty = 'Nothing matches.',
  disabled,
  invalid,
  className,
  'aria-label': ariaLabel,
}: {
  id?: string
  value: string
  onChange: (v: string) => void
  options: Option[]
  placeholder?: string
  searchPlaceholder?: string
  empty?: string
  disabled?: boolean
  invalid?: boolean
  className?: string
  'aria-label'?: string
}) {
  const [open, setOpen] = useState(false)
  const current = options.find((o) => o.value === value)
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          id={id}
          type="button"
          variant="outline"
          role="combobox"
          aria-expanded={open}
          aria-invalid={invalid || undefined}
          aria-label={ariaLabel}
          disabled={disabled}
          className={cn('w-full justify-between px-3 font-normal shadow-none', !current && 'text-muted-foreground', className)}
        >
          <span className="truncate">{current?.label ?? placeholder}</span>
          <ChevronsUpDown aria-hidden className="size-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-(--radix-popover-trigger-width) min-w-56 p-0">
        <Command>
          <CommandInput placeholder={searchPlaceholder} />
          <CommandList>
            <CommandEmpty>{empty}</CommandEmpty>
            <CommandGroup>
              {options.map((o) => (
                <CommandItem
                  key={o.value}
                  value={o.value}
                  keywords={[o.label, ...(o.hint ? [o.hint] : []), ...(o.keywords ?? [])]}
                  onSelect={() => {
                    onChange(o.value)
                    setOpen(false)
                  }}
                >
                  <Check aria-hidden className={cn('size-4', o.value === value ? 'opacity-100' : 'opacity-0')} />
                  <span className="truncate">{o.label}</span>
                  {o.hint && <span className="ml-auto pl-3 text-xs text-ink-faint">{o.hint}</span>}
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}

/** Inclusive Phnom Penh day range, as `YYYY-MM-DD` strings. */
export type DayRange = { from: string; to: string }

const PRESETS: { label: string; range: () => DayRange }[] = [
  { label: 'Today', range: () => ({ from: ppDay(), to: ppDay() }) },
  { label: 'Yesterday', range: () => ({ from: ppDay(-1), to: ppDay(-1) }) },
  { label: 'Last 7 days', range: () => ({ from: ppDay(-6), to: ppDay() }) },
  { label: 'This month', range: () => ({ from: dayjs(ppDay()).startOf('month').format('YYYY-MM-DD'), to: ppDay() }) },
  {
    label: 'Last month',
    range: () => {
      const m = dayjs(ppDay()).subtract(1, 'month')
      return { from: m.startOf('month').format('YYYY-MM-DD'), to: m.endOf('month').format('YYYY-MM-DD') }
    },
  },
]

const toDate = (d: string) => dayjs(d).toDate()
const toDay = (d: Date) => dayjs(d).format('YYYY-MM-DD')

export function rangeLabel({ from, to }: DayRange) {
  if (from === to) return fmtDay(from)
  const sameYear = from.slice(0, 4) === to.slice(0, 4)
  return `${fmtDay(from, sameYear ? 'D MMM' : 'D MMM YYYY')} – ${fmtDay(to)}`
}

export function DateRangePicker({ id, value, onChange }: { id?: string; value: DayRange; onChange: (r: DayRange) => void }) {
  const [open, setOpen] = useState(false)
  const [draft, setDraft] = useState<DateRange | undefined>()
  const selected = draft ?? { from: toDate(value.from), to: toDate(value.to) }
  const commit = (r: DayRange) => {
    onChange(r)
    setDraft(undefined)
    setOpen(false)
  }
  return (
    <Popover
      open={open}
      onOpenChange={(o) => {
        setOpen(o)
        if (!o) setDraft(undefined)
      }}
    >
      <PopoverTrigger asChild>
        <Button id={id} type="button" variant="outline" className="min-w-60 justify-start gap-2 px-3 font-normal shadow-none">
          <CalendarDays aria-hidden className="size-4 text-ink-faint" />
          <span className="tabular">{rangeLabel(value)}</span>
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="flex w-auto flex-col p-0 sm:flex-row">
        <div className="flex flex-row flex-wrap gap-1 border-b border-thread p-2 sm:w-36 sm:flex-col sm:border-r sm:border-b-0">
          {PRESETS.map((p) => (
            <Button key={p.label} type="button" variant="ghost" size="sm" className="justify-start font-normal" onClick={() => commit(p.range())}>
              {p.label}
            </Button>
          ))}
        </div>
        <Calendar
          mode="range"
          numberOfMonths={2}
          defaultMonth={dayjs(value.from).toDate()}
          selected={selected}
          disabled={{ after: toDate(ppDay()) }}
          onSelect={(_r, day) => {
            // First click starts a new range; the second click closes it.
            if (!draft?.from) return setDraft({ from: day, to: undefined })
            const [a, b] = [toDay(draft.from), toDay(day)].sort()
            commit({ from: a, to: b })
          }}
        />
      </PopoverContent>
    </Popover>
  )
}

/** A short exclusive choice shown inline (payment method, charge by). Radix ToggleGroup = radio semantics. */
export function Segmented({
  id,
  value,
  onChange,
  options,
  className,
  'aria-label': ariaLabel,
}: {
  id?: string
  value: string
  onChange: (v: string) => void
  options: Option[]
  className?: string
  'aria-label'?: string
}) {
  return (
    <ToggleGroup
      id={id}
      type="single"
      value={value}
      // Radix sends '' when the active item is clicked again; keep the current choice.
      onValueChange={(v) => v && onChange(v)}
      aria-label={ariaLabel}
      className={cn('grid w-full auto-cols-fr grid-flow-col gap-1 rounded-weave bg-sunk p-1', className)}
    >
      {options.map((o) => (
        <ToggleGroupItem
          key={o.value}
          value={o.value}
          className="h-8 rounded-md text-[13px] text-ink-soft hover:bg-surface/60 hover:text-ink data-[state=on]:bg-surface data-[state=on]:text-ink data-[state=on]:ring-1 data-[state=on]:ring-thread-strong"
        >
          {o.label}
        </ToggleGroupItem>
      ))}
    </ToggleGroup>
  )
}
