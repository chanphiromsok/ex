<!-- impeccable:product-schema 1 -->
# Express Cargo — Staff Portal

## Platform
web (desktop-first, works down to tablet widths)

## Users
- **Station Staff** at a counter: accept walk-in Senders, create Shipments, take Payments, move Shipments (In Transit / Arrived), hand Parcels to Receivers after a phone match.
- **Supervisors**: everything staff do, plus approving Cancellations and Receiver Corrections at their Station.
- **Admins**: company-wide, no Station; maintain pricing, Locations/Stations/Routes, Station Settings, users; resolve Incidents.

## Product Purpose
The counter tool for an express cargo business that carries goods by bus between Stations across Cambodia. Its job is to make a counter transaction fast and correct while a queue waits, and to make every money and status change traceable.

## Positioning
An internal operations tool, not a customer product. Success is speed, zero ambiguity about money and status, and staff trusting what they see.

## Operating Context
- Counter desktop or laptop, keyboard and mouse, often a queue of customers waiting.
- Staff type phone numbers and Invoice Numbers repeatedly; search and forms must be keyboard-friendly.
- Money is KHR (៛), amounts are large integers; totals must be impossible to misread.
- Report days are Asia/Phnom_Penh (UTC+7).

## Capabilities and Constraints
- TanStack Start + React 19 + Tailwind v4 SPA (ssr:false behind login) talking JSON:API to a Phoenix/Ash backend.
- Menu items and actions are driven by the user's Permissions; hidden means not permitted.
- Status Events and Payments are append-only; the UI never offers edit or delete for them.
- Existing element IDs (`#login-form`, `#shipment-form`, `#submit-shipment`, `#invoice-no`, `menu-<slug>` etc.) are used by tests and must be kept.
- No component library or icon dependency yet.

## Brand Commitments
Name: Express Cargo. No logo, palette or fonts exist yet; a look may be proposed.

## Evidence on Hand
GLOSSARY.md (domain language, to be used verbatim in UI copy), docs/adr/*, existing client screens.

## Product Principles
1. The counter flow comes first: New Shipment and Shipment lookup must be fastest.
2. Money and status are always unambiguous: clear totals, explicit status, explicit who/where/when.
3. Use the glossary's words (Shipment, Parcel, Invoice Number, Collection…), never its "avoid" words.
4. Only show what the user may do.

## Accessibility & Inclusion
- UI chrome in English; Khmer names shown alongside English for Locations, Stations, Size Classes, Sale Items and status labels. Khmer text needs a font with proper Khmer shaping and enough line height.
- WCAG AA contrast, visible focus states, full keyboard operation.
