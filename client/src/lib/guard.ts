import { notFound } from '@tanstack/react-router'
import { findItem } from '#/lib/menu'
import type { Session } from '#/lib/auth'

/**
 * Route guard for a menu screen. Passes when the signed-in user holds ANY of the menu item's permissions
 * (or, when `only` is given, any of those instead), otherwise the route is a 404, the same as an unknown URL.
 * Put it in `beforeLoad` of the screen's top route; nested routes inherit it.
 */
export function guard(slug: string, only?: string[]) {
  return ({ context }: { context: { session: Session } }) => {
    const item = findItem(slug)
    const needs = only ?? item?.permissions
    if (!item || !needs?.some((p) => context.session.permissions.includes(p))) throw notFound()
    return { item }
  }
}
