import { isValidPhoneNumber, parsePhoneNumberFromString } from 'libphonenumber-js'
import { z } from 'zod'

/**
 * Cambodian phones only — mirrors `Ex.Shipping.Phone` on the server, which stores
 * them as `855…` digits. People type `012 345 678`, `+855 12 345 678`, `00855…`
 * or the stored `85512345678`; all of those are accepted here.
 */
function asInternational(input: string): string {
  const v = input.trim().replace(/[\s\-.()]/g, '')
  if (v.startsWith('00')) return `+${v.slice(2)}`
  if (v.startsWith('855')) return `+${v}`
  return v
}

export function isCambodianPhone(input: string): boolean {
  const v = asInternational(input)
  if (!isValidPhoneNumber(v, 'KH')) return false
  return parsePhoneNumberFromString(v, 'KH')?.country === 'KH'
}

/** `85512345678` → `012 345 678`; anything unparseable is shown as given. */
export function formatPhone(stored: string | null | undefined): string {
  if (!stored) return ''
  const p = parsePhoneNumberFromString(asInternational(stored), 'KH')
  return p?.isValid() ? p.formatNational() : stored
}

/** `tel:` target in E.164 so it dials correctly from any phone. */
export function phoneHref(stored: string | null | undefined): string {
  if (!stored) return ''
  const p = parsePhoneNumberFromString(asInternational(stored), 'KH')
  return `tel:${p?.isValid() ? p.number : stored}`
}

export const phoneSchema = z
  .string()
  .trim()
  .min(1, 'Enter a phone number.')
  .refine(isCambodianPhone, 'Enter a Cambodian number, e.g. 012 345 678.')
