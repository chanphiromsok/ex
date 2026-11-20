---
version: 1
slug: "src-routes-app-tsx"
primary_target: "src/routes/_app.tsx"
related_targets: ["src/pages","src/routes/login.tsx"]
---

# Staff portal shell and screens

Scope: the whole staff portal (login, app shell, every screen under src/pages). Mode: Operate.
Audience and job: Station Staff, Supervisors and Admins at a counter desktop; create Shipments, find them by Invoice Number or phone, move and collect them, follow up Cancellations, Incidents and Overdue Shipments, run cash reports, maintain reference data.
Constraints: keep every existing element ID; permission-driven menus/actions; English UI text, Khmer names shown alongside English.

## Direction contract
THESIS: The portal reads like a well-woven krama: plain, sturdy and tightly organised, with one woven band that tells a Shipment's whole life at a glance. It refuses the grey SaaS admin with a blue accent and stat cards.
OWN-WORLD: Deep indigo rail and header ink, warm undyed-cotton ground, white work surfaces with 1px thread-coloured rules, madder red reserved for money owed, alerts and cancellation, a muted turmeric for waiting/approval. Workhorse sans (Inter Tight for Latin, Kantumruy Pro for Khmer), tabular figures for every Invoice Number and ៛ amount. 8px radii on surfaces, no shadows except menus and dialogs.
STORY: Staff see where they are, what needs action, and the exact money and status of any Shipment without hunting, then act with one clear primary button.
FIRST VIEWPORT: Indigo sidebar left (brand, grouped menu, user at foot); main column with page title + primary action on one line, then a filter bar, then the work table. On a Shipment: header with Invoice Number, route and Shipment Total, the full-width status weave under it, then parcels, payments and history.
FORM: Krama weave, candidate 7 of 7 on the ordered list (seed:7ad44e4390d96b43). Signature move: the status weave, four warp stripes (Received, In Transit, Arrived, Collected) filled as events occur; cancelled cuts the band in madder.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
