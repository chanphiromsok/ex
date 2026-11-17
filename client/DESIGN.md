# Express Cargo staff portal — design system

A counter tool for parcel staff in Cambodia. It's used all day, often in a hurry, sometimes while the customer is still at the counter. Each design choice should help someone take payment and hand over the Invoice faster.

## Direction

- **Claude-style: calm ivory, one clay accent.** Warm ivory background (`ground`), white working surfaces (`surface`) with soft hairlines, near-black `ink`, and `clay` (terracotta) for the brand mark, primary actions, focus and progress. The sidebar is a light rail one step deeper than the ground. Use no other decorative colour.
- **Serif for headings only.** Page titles, the sign-in screen and the wordmark use Source Serif 4 at normal weight. Everything you operate (labels, tables, buttons, numbers) stays in the sans.
- **Colour carries meaning only.** `madder` = money going out / destructive / errors, `turmeric` = waiting (pending, active nav marker), `leaf` = done (approved, resolved, saved). Avoid decorative colour.
- **Numbers are first-class.** Money and counts use `tabular` figures, are right-aligned in tables, and show riel as `៛`.
- **Bilingual.** English is primary. Khmer names appear underneath via `<Bilingual>` and use Kantumruy Pro at 1.7 line-height (`:lang(km)`). Never write new Khmer copy without a native speaker; only show Khmer that comes from the data.

## Tokens (`src/styles.css` `@theme`)

| Role | Token |
| --- | --- |
| Page background / sunken wells | `ground`, `sunk` |
| Cards, inputs | `surface` |
| Borders (hairline / emphasis) | `thread`, `thread-strong` |
| Text (primary / secondary / hint) | `ink`, `ink-soft`, `ink-faint` |
| Brand, primary buttons, focus ring | `clay` (+ `-deep`, `-wash`) |
| Sidebar | `rail`, `rail-line`, `on-rail`, `on-rail-soft` |
| Danger / refunds / errors | `madder` (+ `-deep`, `-wash`) |
| Pending / attention | `turmeric` (+ `-ink`, `-wash`) |
| Success | `leaf` (+ `-wash`) |
| Radius | `rounded-weave` / `--radius` (10px); pills are fully rounded |
| Motion | `ease-out-expo`, 150–300ms; all motion is off under `prefers-reduced-motion` |

Type: Inter Tight Variable (UI) + Source Serif 4 Variable (`font-serif`, headings) + Kantumruy Pro Variable (Khmer), base 14px. Page title 28px serif regular, card title 15px sans semibold, labels 13px medium. White text on `clay` meets 4.5:1. Don't lighten `clay` for primary buttons.

## Components

Primitives come from shadcn/ui (`src/components/ui/*`, new-york, themed by the tokens above). Do not edit them for one-off looks; wrap them instead.

- `src/components/kit.tsx`: `Page` (title, subtitle, `action`, back button, max width 1180px); `Card` (the only container; use `flush` for edge-to-edge tables; never nest Cards); `Tray` (a Card's footer strip that holds an "add a row" form); `Button` (shadcn Button plus a `busy` spinner and `icon`); `Err` (role=alert); `Pill` tones; `Num` (tabular); `Bilingual`; `Detail`.
- `src/components/form.tsx`: `FormField` (react-hook-form Controller with label, description, and error), `Choice` (Select, for short fixed lists), `Combobox` (searchable, for Stations and Locations), `Segmented`, `DateRangePicker` (presets plus a two-month calendar).
- `src/components/data-table.tsx`: `DataTable` on TanStack Table, with sortable headers (`aria-sort`), a global search that also matches digits only, pagination, skeleton rows, an empty state, clickable rows, and `FooterRow`/`FooterCell` for totals.
- `src/components/confirm-dialog.tsx`: `ConfirmDialog` for anything destructive.
- `StatusWeave` / `StatusTag` (`src/components/StatusWeave.tsx`): the Shipment lifecycle as four stripes (Received → In transit → Arrived → Collected). The current stripe is hatched; Cancelled turns it into a madder line.

## Rules

- Data loading uses TanStack Query only (`listQuery`, `recordQuery`, `rawQuery` in `src/lib/queries.ts`). Writes use `useMutation` and invalidate `apiKey('<resource>')`.
- Forms use react-hook-form + zod (`zodResolver`). Successful writes confirm with a `sonner` toast.
- Dates use dayjs only (`src/lib/date.ts`, Asia/Phnom_Penh): `when`, `ago`, `ppDay`, `dayStartUtc`. Do not add date-fns.
- Phones use `src/lib/phone.ts` (libphonenumber-js, Cambodia only, which matches the server's `Ex.Shipping.Phone`): validate with `phoneSchema`, show with `formatPhone`, and link with `phoneHref`.
- Shadows are only for floating layers (menus, the mobile drawer). Cards use hairline borders.
- Every action button shows its own busy state; with row actions, only the clicked row spins.
- Use the domain terms from the glossary: Shipment, Parcel, Invoice, Station, Sale Item, Size Class, Cancellation, Incident, Overdue.
- Keep existing element IDs (`#login-form`, `#shipment-form`, `#invoice-no`, `#cancel`, …); tests and scripts rely on them.
