import { useEffect, type ReactNode } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Textarea } from '@/components/ui/textarea'
import { Button, Err } from '#/components/kit'
import { FormField } from '#/components/form'

const schema = z.object({ text: z.string().trim().min(3, 'Write at least a few words.') })

/**
 * A small dialog that asks for one required piece of text (a reject reason,
 * an Incident resolution) before running the action.
 */
export function ReasonDialog({
  open,
  onOpenChange,
  title,
  description,
  label,
  fieldId,
  confirm,
  tone = 'default',
  busy,
  error,
  onConfirm,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: ReactNode
  description?: ReactNode
  label: string
  fieldId: string
  confirm: string
  tone?: 'default' | 'destructive'
  busy?: boolean
  error?: unknown
  onConfirm: (text: string) => void
}) {
  const form = useForm({ resolver: zodResolver(schema), defaultValues: { text: '' } })
  useEffect(() => {
    if (open) form.reset({ text: '' })
  }, [open, form])

  return (
    <Dialog open={open} onOpenChange={(o) => !busy && onOpenChange(o)}>
      <DialogContent className="sm:max-w-md">
        <form noValidate onSubmit={form.handleSubmit((v) => onConfirm(v.text))} className="grid gap-4">
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            {description && <DialogDescription>{description}</DialogDescription>}
          </DialogHeader>
          <FormField control={form.control} name="text" label={label} id={fieldId}>
            {(f) => <Textarea {...f} autoFocus rows={3} className="resize-none" />}
          </FormField>
          <Err error={error} />
          <DialogFooter>
            <Button variant="outline" disabled={busy} onClick={() => onOpenChange(false)}>
              Back
            </Button>
            <Button type="submit" variant={tone} busy={busy}>
              {confirm}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
