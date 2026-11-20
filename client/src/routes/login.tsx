import { useMutation } from '@tanstack/react-query'
import { createFileRoute, redirect, useNavigate } from '@tanstack/react-router'
import { getSession, signIn } from '#/lib/auth'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Button, Err } from '#/components/kit'
import { FormField } from '#/components/form'
import { Input } from '@/components/ui/input'
import { BrandMark } from '#/components/nav'

export const Route = createFileRoute('/login')({
  ssr: false,
  beforeLoad: () => {
    if (getSession()) throw redirect({ to: '/' })
  },
  component: Login,
})

const schema = z.object({
  login: z.string().trim().min(1, 'Enter your phone number or email.'),
  password: z.string().min(1, 'Enter your password.'),
})
type Values = z.infer<typeof schema>

function Login() {
  const navigate = useNavigate()
  const login = useMutation({
    mutationFn: ({ login, password }: Values) => signIn(login, password),
    onSuccess: () => navigate({ to: '/' }),
  })
  const form = useForm<Values>({ resolver: zodResolver(schema), defaultValues: { login: '', password: '' } })

  return (
    <main className="grid min-h-screen lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
      <section className="relative hidden overflow-hidden border-r border-rail-line bg-rail px-12 py-12 text-on-rail lg:flex lg:flex-col lg:justify-between">
        <div className="flex items-center gap-2.5">
          <BrandMark className="size-6 text-clay" />
          <span className="font-serif text-lg font-medium">Express Cargo</span>
        </div>
        <div className="max-w-sm">
          <p className="font-serif text-[34px] leading-[1.15] font-normal tracking-[-0.015em] text-balance">Every Shipment, from counter to Collection.</p>
        </div>
        {/* The four warp stripes of the status weave, as a quiet signature. */}
        <div aria-hidden className="grid grid-cols-4 gap-1.5">
          <span className="h-2.5 rounded-[3px] bg-clay" />
          <span className="h-2.5 rounded-[3px] bg-clay" />
          <span className="h-2.5 rounded-[3px] bg-clay weave-hatch" />
          <span className="h-2.5 rounded-[3px] bg-thread-strong" />
        </div>
      </section>

      <section className="flex items-center justify-center bg-ground px-5 py-16">
        <form id="login-form" noValidate onSubmit={form.handleSubmit((v) => login.mutate(v))} className="w-full max-w-[360px]">
          <div className="mb-8 flex items-center gap-2.5 lg:hidden">
            <BrandMark className="size-6 text-clay" />
            <span className="font-serif text-lg font-medium">Express Cargo</span>
          </div>
          <h1 className="font-serif text-[28px] font-normal tracking-[-0.015em]">Sign in</h1>
          <p className="mt-1 text-sm text-ink-soft">Use the staff account your admin gave you.</p>

          <div className="mt-7 space-y-4">
            <FormField control={form.control} name="login" label="Phone number or email" id="login">
              {(field) => <Input {...field} inputMode="text" autoComplete="username" autoFocus className="h-10" />}
            </FormField>
            <FormField control={form.control} name="password" label="Password" id="password">
              {(field) => <Input {...field} type="password" autoComplete="current-password" className="h-10" />}
            </FormField>
            {login.isError && <Err id="login-error" error={login.error} />}
            <Button id="login-submit" type="submit" busy={login.isPending} className="h-10 w-full">
              {login.isPending ? 'Signing in…' : 'Sign in'}
            </Button>
          </div>
        </form>
      </section>
    </main>
  )
}
