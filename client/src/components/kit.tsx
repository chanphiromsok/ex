import type { ComponentProps, ReactNode } from 'react'
import { AlertCircle, ArrowLeft, LoaderCircle } from 'lucide-react'
import { Button as UIButton } from '@/components/ui/button'
import { cn } from '@/lib/utils'

/** shadcn Button plus a busy spinner and a leading icon. */
export function Button({
  busy = false,
  icon,
  children,
  disabled,
  type = 'button',
  ...props
}: ComponentProps<typeof UIButton> & { busy?: boolean; icon?: ReactNode }) {
  return (
    <UIButton type={type} disabled={disabled || busy} aria-busy={busy || undefined} {...props}>
      {busy ? <LoaderCircle aria-hidden className="size-4 animate-spin" /> : icon}
      {children}
    </UIButton>
  )
}

export function Page({
  title,
  subtitle,
  action,
  onBack,
  backLabel = 'Back',
  bare = false,
  children,
}: {
  title: ReactNode
  subtitle?: ReactNode
  action?: ReactNode
  onBack?: () => void
  backLabel?: string
  /** Skip the title block; the sidebar already names the screen. */
  bare?: boolean
  children: ReactNode
}) {
  return (
    <div className="mx-auto max-w-[1180px] px-5 pt-6 pb-20 sm:px-8 lg:px-10">
      {onBack && (
        <button
          type="button"
          onClick={onBack}
          className="no-print mb-3 inline-flex items-center gap-1.5 rounded-md text-[13px] font-medium text-ink-soft transition-colors hover:text-ink"
        >
          <ArrowLeft aria-hidden className="size-3.5" />
          {backLabel}
        </button>
      )}
      {!bare && (
      <header className="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div className="min-w-0">
          <h1 className="font-serif text-[28px] leading-tight font-normal tracking-[-0.015em] text-balance">{title}</h1>
          {subtitle && <p className="mt-1 text-sm text-ink-soft">{subtitle}</p>}
        </div>
        {action && <div className="no-print flex items-center gap-2">{action}</div>}
      </header>
      )}
      <div className="space-y-5">{children}</div>
    </div>
  )
}

export function Card({
  title,
  description,
  actions,
  flush = false,
  id,
  className,
  children,
}: {
  title?: ReactNode
  description?: ReactNode
  actions?: ReactNode
  flush?: boolean
  id?: string
  className?: string
  children: ReactNode
}) {
  return (
    <section id={id} className={cn('overflow-hidden rounded-weave border border-thread bg-surface', className)}>
      {(title || actions) && (
        <header className="flex flex-wrap items-start justify-between gap-3 border-b border-thread px-5 py-3.5">
          <div className="min-w-0">
            {title && <h2 className="text-[15px] font-semibold tracking-[-0.01em]">{title}</h2>}
            {description && <p className="mt-0.5 text-[13px] text-ink-soft">{description}</p>}
          </div>
          {actions && <div className="flex items-center gap-2">{actions}</div>}
        </header>
      )}
      <div className={flush ? '' : 'space-y-4 p-5'}>{children}</div>
    </section>
  )
}

/** Footer strip of a Card. */
export function Tray({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('border-t border-thread bg-ground/60 px-5 py-4', className)}>{children}</div>
}

export function errorText(error: unknown): string {
  if (!error) return ''
  if (error instanceof Error) return error.message
  return String(error)
}

export function Err({ error, id }: { error: unknown; id?: string }) {
  if (!error) return null
  return (
    <div
      id={id}
      role="alert"
      className="flex items-start gap-2.5 rounded-weave border border-madder/25 bg-madder-wash px-3.5 py-2.5 text-sm text-madder-deep"
    >
      <AlertCircle aria-hidden className="mt-0.5 size-4 shrink-0" />
      <span>{errorText(error)}</span>
    </div>
  )
}

export function Bilingual({ en, km, className }: { en: ReactNode; km?: ReactNode; className?: string }) {
  return (
    <span className={cn('block', className)}>
      <span className="block text-ink">{en}</span>
      {km && (
        <span lang="km" className="block text-[12.5px] leading-snug text-ink-faint">
          {km}
        </span>
      )}
    </span>
  )
}

export function Num({ children, className }: { children: ReactNode; className?: string }) {
  return <span className={cn('tabular whitespace-nowrap', className)}>{children}</span>
}

const tones = {
  neutral: 'bg-sunk text-ink-soft',
  clay: 'bg-clay-wash text-clay',
  turmeric: 'bg-turmeric-wash text-turmeric-ink',
  madder: 'bg-madder-wash text-madder-deep',
  leaf: 'bg-leaf-wash text-leaf',
}

export function Pill({ tone = 'neutral', children }: { tone?: keyof typeof tones; children: ReactNode }) {
  return (
    <span className={cn('inline-flex h-6 items-center rounded-full px-2.5 text-xs font-medium whitespace-nowrap', tones[tone])}>
      {children}
    </span>
  )
}

/** A label/value pair for read-only detail blocks. */
export function Detail({ label, children }: { label: ReactNode; children: ReactNode }) {
  return (
    <div>
      <dt className="text-xs font-medium text-ink-faint">{label}</dt>
      <dd className="mt-0.5">{children}</dd>
    </div>
  )
}
