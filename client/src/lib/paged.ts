import { useEffect, useMemo, useState } from 'react'
import { useInfiniteQuery } from '@tanstack/react-query'
import type { Rec } from './api'
import { asRows, nextCursor } from './queries'

/**
 * One page of rows at a time, with Previous / Next for `DataTable`'s `more` prop.
 * Pass a generated infinite query (`getXInfiniteOptions(...)`). Next opens a page already
 * fetched, or asks the server for the next cursor. Pages go back to the first whenever
 * `resetKey` changes (a new search or filter).
 *
 *   const t = usePaged(getIncidentsInfiniteOptions())
 *   <DataTable data={t.rows} loading={t.isPending} more={t.more} />
 */
export function usePaged(options: any, resetKey: unknown = ''): { rows: Rec[]; isPending: boolean; isError: boolean; isSuccess: boolean; error: unknown; data: Rec[]; more: any } {
  const q = useInfiniteQuery({
    ...options,
    initialPageParam: {} as Record<string, unknown>,
    getNextPageParam: nextCursor,
    select: (d: any) => d.pages.map((p: any) => asRows(p)) as Rec[][],
  } as any) as any
  const [page, setPage] = useState(0)
  useEffect(() => setPage(0), [resetKey])
  const pages: Rec[][] = q.data ?? []
  const rows = useMemo(() => pages[Math.min(page, Math.max(pages.length - 1, 0))] ?? [], [pages, page])
  return {
    rows,
    isPending: q.isPending,
    isError: q.isError,
    isSuccess: q.isSuccess,
    error: q.error,
    data: rows,
    more: {
      page,
      hasNext: page + 1 < pages.length || !!q.hasNextPage,
      loading: q.isFetchingNextPage,
      onPrev: () => setPage((n) => Math.max(0, n - 1)),
      onNext: async () => {
        if (page + 1 >= pages.length) await q.fetchNextPage()
        setPage((n) => n + 1)
      },
    },
  }
}
