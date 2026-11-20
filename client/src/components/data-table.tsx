import { useState, type ReactNode } from 'react'
import {
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type FilterFn,
  type Row,
  type RowData,
  type SortingState,
} from '@tanstack/react-table'
import { ArrowDown, ArrowUp, ChevronLeft, ChevronRight, ChevronsUpDown, Inbox, Search } from 'lucide-react'
import { Table, TableBody, TableCell, TableFooter, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'

declare module '@tanstack/react-table' {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  interface ColumnMeta<TData extends RowData, TValue> {
    align?: 'left' | 'right' | 'center'
    className?: string
  }
}

export type { ColumnDef }

const alignClass = { left: 'text-left', right: 'text-right', center: 'text-center' }

/** Search across every column's accessor value (as text), case-insensitive, digits-aware for phones. */
const textFilter: FilterFn<unknown> = (row, columnId, needle: string) => {
  const q = String(needle ?? '').trim().toLowerCase()
  if (!q) return true
  const v = row.getValue(columnId)
  if (v == null) return false
  const s = String(v).toLowerCase()
  if (s.includes(q)) return true
  const digits = q.replace(/\D/g, '')
  return digits.length >= 3 && s.replace(/\D/g, '').includes(digits)
}

export function DataTable<T>({
  id,
  columns,
  data,
  loading = false,
  empty = 'Nothing here yet.',
  search,
  toolbar,
  onRowClick,
  rowLabel,
  pageSize = 20,
  initialSort,
  footer,
  rowClassName,
  scrollHeight,
  serverSearch,
  more,
}: {
  id?: string
  columns: ColumnDef<T, any>[]
  data: T[] | undefined
  loading?: boolean
  empty?: ReactNode
  /** Shows a search box filtering all columns; `id` keeps existing selectors working. */
  search?: { id?: string; placeholder?: string; label?: string; autoFocus?: boolean }
  /** Extra controls rendered right of the search box. */
  toolbar?: ReactNode
  /** Tailwind max-height class (e.g. `max-h-[65vh]`). Rows scroll inside it while the search box and header stay put. */
  scrollHeight?: string
  onRowClick?: (row: T) => void
  rowLabel?: (row: T) => string
  pageSize?: number
  initialSort?: SortingState
  footer?: ReactNode
  rowClassName?: (row: T) => string | undefined
  /** The parent owns the search text and filters on the server; rows are shown as given. */
  serverSearch?: { value: string; onChange: (v: string) => void }
  /** Server pages: Previous / Next centered under the rows; `rows` is the current page only. */
  more?: { page: number; hasNext: boolean; loading: boolean; onPrev: () => void; onNext: () => void }
}) {
  const [sorting, setSorting] = useState<SortingState>(initialSort ?? [])
  const [localFilter, setLocalFilter] = useState('')
  const globalFilter = serverSearch ? '' : localFilter
  const searchText = serverSearch ? serverSearch.value : localFilter
  // With server pages every loaded row is shown; Next fetches the next page.
  const [pagination, setPagination] = useState({ pageIndex: 0, pageSize: more ? Number.MAX_SAFE_INTEGER : pageSize })

  const table = useReactTable({
    data: data ?? [],
    columns,
    state: { sorting, globalFilter, pagination },
    onSortingChange: setSorting,
    onGlobalFilterChange: (v) => {
      setLocalFilter(v)
      setPagination((p) => ({ ...p, pageIndex: 0 }))
    },
    onPaginationChange: setPagination,
    globalFilterFn: textFilter as FilterFn<T>,
    getColumnCanGlobalFilter: () => true,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    autoResetPageIndex: false,
  })

  const rows = table.getRowModel().rows
  const total = table.getFilteredRowModel().rows.length
  const pageCount = table.getPageCount()
  const { pageIndex } = table.getState().pagination
  const first = total === 0 ? 0 : pageIndex * pagination.pageSize + 1
  const last = Math.min(total, (pageIndex + 1) * pagination.pageSize)
  const colCount = table.getVisibleLeafColumns().length

  const open = (row: Row<T>) => onRowClick?.(row.original)

  return (
    <div id={id}>
      {(search || toolbar) && (
        <div className="flex flex-wrap items-center gap-2 border-b border-thread px-5 py-3">
          {search && (
            <div className="relative min-w-0 flex-1 sm:max-w-sm">
              <Search aria-hidden className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-ink-faint" />
              <Input
                id={search.id}
                type="search"
                autoFocus={search.autoFocus}
                value={searchText}
                onChange={(e) => (serverSearch ? serverSearch.onChange(e.target.value) : table.setGlobalFilter(e.target.value))}
                placeholder={search.placeholder ?? 'Search…'}
                aria-label={search.label ?? search.placeholder ?? 'Search'}
                className="pl-9 shadow-none"
              />
            </div>
          )}
          {toolbar && <div className="ml-auto flex flex-wrap items-center gap-2">{toolbar}</div>}
        </div>
      )}

      <Table containerClassName={scrollHeight ? cn('overflow-y-auto overscroll-contain', scrollHeight) : undefined}>
        <TableHeader className={scrollHeight ? 'sticky top-0 z-10 bg-sunk shadow-[0_1px_0_var(--color-thread)]' : 'bg-sunk/70'}>
          {table.getHeaderGroups().map((hg) => (
            <TableRow key={hg.id} className="border-thread hover:bg-transparent">
              {hg.headers.map((h) => {
                const meta = h.column.columnDef.meta
                const align = meta?.align ?? 'left'
                const sorted = h.column.getIsSorted()
                const canSort = h.column.getCanSort() && !h.isPlaceholder
                return (
                  <TableHead
                    key={h.id}
                    aria-sort={sorted === 'asc' ? 'ascending' : sorted === 'desc' ? 'descending' : canSort ? 'none' : undefined}
                    className={cn('h-10 px-3 text-xs font-medium text-ink-soft first:pl-5 last:pr-5', alignClass[align], meta?.className)}
                  >
                    {h.isPlaceholder ? null : canSort ? (
                      <button
                        type="button"
                        onClick={h.column.getToggleSortingHandler()}
                        className={cn(
                          'group/sort -mx-1 inline-flex items-center gap-1 rounded px-1 py-0.5 transition-colors hover:text-ink',
                          align === 'right' && 'flex-row-reverse',
                          sorted && 'text-ink',
                        )}
                      >
                        {flexRender(h.column.columnDef.header, h.getContext())}
                        {sorted === 'asc' ? (
                          <ArrowUp aria-hidden className="size-3.5" />
                        ) : sorted === 'desc' ? (
                          <ArrowDown aria-hidden className="size-3.5" />
                        ) : (
                          <ChevronsUpDown aria-hidden className="size-3.5 opacity-0 transition-opacity group-hover/sort:opacity-60" />
                        )}
                      </button>
                    ) : (
                      flexRender(h.column.columnDef.header, h.getContext())
                    )}
                  </TableHead>
                )
              })}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {loading ? (
            Array.from({ length: 3 }, (_, i) => (
              <TableRow key={i} className="border-thread hover:bg-transparent">
                {Array.from({ length: colCount }, (_, j) => (
                  <TableCell key={j} className="px-3 py-3.5 first:pl-5 last:pr-5">
                    <Skeleton className="h-4 w-full max-w-32 bg-sunk" />
                  </TableCell>
                ))}
              </TableRow>
            ))
          ) : rows.length === 0 ? (
            <TableRow className="hover:bg-transparent">
              <TableCell colSpan={colCount} className="px-5 py-12 text-center whitespace-normal">
                <Inbox aria-hidden className="mx-auto mb-2 size-5 text-ink-faint" />
                <p className="text-sm text-ink-soft">
                  {searchText.trim() ? <>Nothing matches “{searchText.trim()}”.</> : empty}
                </p>
              </TableCell>
            </TableRow>
          ) : (
            rows.map((row) => (
              <TableRow
                key={row.id}
                tabIndex={onRowClick ? 0 : undefined}
                aria-label={onRowClick && rowLabel ? rowLabel(row.original) : undefined}
                onClick={onRowClick ? () => open(row) : undefined}
                onKeyDown={
                  onRowClick
                    ? (e) => {
                        if (e.target !== e.currentTarget) return
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault()
                          open(row)
                        }
                      }
                    : undefined
                }
                className={cn(
                  'border-thread hover:bg-ground/70',
                  onRowClick && 'cursor-pointer focus-visible:bg-clay-wash/60 focus-visible:outline-none',
                  rowClassName?.(row.original),
                )}
              >
                {row.getVisibleCells().map((cell) => {
                  const meta = cell.column.columnDef.meta
                  return (
                    <TableCell
                      key={cell.id}
                      className={cn('px-3 py-3 align-middle first:pl-5 last:pr-5', alignClass[meta?.align ?? 'left'], meta?.className)}
                    >
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TableCell>
                  )
                })}
              </TableRow>
            ))
          )}
        </TableBody>
        {footer && !loading && rows.length > 0 && <TableFooter className="border-thread bg-sunk/50">{footer}</TableFooter>}
      </Table>

      {more && !loading && rows.length > 0 && (
        <div className="flex items-center justify-center gap-3 border-t border-thread px-5 py-2.5 text-[13px] text-ink-soft">
          <Button variant="ghost" size="icon-sm" aria-label="Previous page" disabled={more.page === 0 || more.loading} onClick={more.onPrev}>
            <ChevronLeft className="size-4" />
          </Button>
          <span className="tabular px-1">Page {more.page + 1}</span>
          <Button id="next-page" variant="ghost" size="icon-sm" aria-label="Next page" disabled={!more.hasNext || more.loading} onClick={more.onNext}>
            <ChevronRight className="size-4" />
          </Button>
        </div>
      )}

      {!more && !loading && total > pagination.pageSize && (
        <div className="flex items-center justify-between gap-3 border-t border-thread px-5 py-2.5 text-[13px] text-ink-soft">
          <span className="tabular">
            {first}–{last} of {total}
          </span>
          <div className="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Previous page"
              disabled={!table.getCanPreviousPage()}
              onClick={() => table.previousPage()}
            >
              <ChevronLeft className="size-4" />
            </Button>
            <span className="tabular px-1">
              Page {pageIndex + 1} of {pageCount}
            </span>
            <Button variant="ghost" size="icon-sm" aria-label="Next page" disabled={!table.getCanNextPage()} onClick={() => table.nextPage()}>
              <ChevronRight className="size-4" />
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

/** Footer row helper for totals. */
export function FooterRow({ children }: { children: ReactNode }) {
  return <TableRow className="border-thread font-medium hover:bg-transparent">{children}</TableRow>
}

export function FooterCell({ children, align = 'left', colSpan }: { children?: ReactNode; align?: 'left' | 'right' | 'center'; colSpan?: number }) {
  return (
    <TableCell colSpan={colSpan} className={cn('px-3 py-3 first:pl-5 last:pr-5', alignClass[align])}>
      {children}
    </TableCell>
  )
}
