# Entity relationship diagram

Generated from the live `ex_dev` schema (foreign keys read from `information_schema`), 26 tables. Render with any Mermaid viewer (GitHub, VS Code "Markdown Preview Mermaid Support").

Conventions: uuid primary keys, `inserted_at` on every table, money columns are `money_with_currency` (KHR), enums are plain `text`. Column lists show the important columns only; audit columns (`inserted_at`, `created_by_id`) are omitted where noted.

## 1. Network and people

```mermaid
erDiagram
    locations ||--o{ stations : "location_id"
    locations ||--o{ routes : "origin_location_id"
    locations ||--o{ routes : "destination_location_id"
    stations  ||--o{ users : "station_id (nullable)"
    users     ||--o{ refresh_tokens : "user_id"
    users     ||--o{ user_assignment_changes : "user_id"
    stations  ||--o{ user_assignment_changes : "station_id"
    permissions ||--o{ role_permissions : "permission"

    locations { uuid id PK
        text name_en
        text name_km }
    stations { uuid id PK
        uuid location_id FK
        text name_en
        bool active
        bool cancellation_requires_approval
        int overdue_threshold_days
        text external_id }
    routes { uuid id PK
        uuid origin_location_id FK
        uuid destination_location_id FK }
    users { uuid id PK
        ci_string email
        text phone
        text role
        uuid station_id FK
        text hashed_password }
    refresh_tokens { uuid id PK
        uuid user_id FK
        text token_hash
        uuid family_id
        ts expires_at
        ts used_at
        ts revoked_at }
    tokens { text jti PK
        text subject
        text purpose
        ts expires_at }
    permissions { text name PK
        bool station_bound
        text description }
    role_permissions { uuid id PK
        text role
        text permission FK }
    user_assignment_changes { uuid id PK
        uuid user_id FK
        uuid station_id FK
        uuid changed_by_id FK
        text role }
```

`tokens` (AshAuthentication token store) has no foreign key; `subject` is the user reference as text. `role` is an enum in `users` and `role_permissions`, not a table.

## 2. Shipping core

```mermaid
erDiagram
    stations ||--o{ shipments : "origin_station_id"
    stations ||--o{ shipments : "destination_station_id"
    routes   ||--o{ shipments : "route_id"
    users    ||--o{ shipments : "created_by_id"
    manifests |o--o{ shipments : "manifest_id (nullable)"
    stations ||--o{ manifests : "origin_station_id"
    stations ||--o{ manifests : "destination_station_id"
    users    ||--o{ manifests : "created_by_id"

    shipments ||--|{ parcels : "shipment_id"
    size_classes |o--o{ parcels : "size_class_id (nullable)"
    shipments ||--o{ shipment_sale_items : "shipment_id"
    sale_items ||--o{ shipment_sale_items : "sale_item_id"

    shipments ||--o{ status_events : "shipment_id"
    shipments ||--o{ payments : "shipment_id"
    status_events |o--o{ payments : "status_event_id (nullable)"

    shipments { uuid id PK
        bigint invoice_no UK
        uuid idempotency_key UK
        text sender_phone
        text receiver_phone
        money declared_value
        money shipment_total
        text status
        uuid origin_station_id FK
        uuid destination_station_id FK
        uuid route_id FK
        uuid manifest_id FK
        uuid created_by_id FK }
    parcels { uuid id PK
        uuid shipment_id FK
        uuid size_class_id FK
        text measurement_type
        numeric weight_kg
        money chargeable_amount }
    shipment_sale_items { uuid id PK
        uuid shipment_id FK
        uuid sale_item_id FK
        bigint quantity
        money unit_price }
    manifests { uuid id PK
        text external_trip_id
        ts departs_at
        text bus_label
        text status
        ts departed_at
        ts arrived_at
        uuid origin_station_id FK
        uuid destination_station_id FK }
    status_events { uuid id PK
        uuid shipment_id FK
        bigint seq
        text status
        text reason
        uuid station_id FK
        uuid created_by_id FK }
    payments { uuid id PK
        uuid shipment_id FK
        uuid status_event_id FK
        text kind
        text method
        money amount
        uuid station_id FK
        uuid created_by_id FK }
```

`shipments.status` is stored on the row as well as in the `status_events` history (`status_events` is the source of truth; unique `seq` per shipment). `shipment_sale_items.unit_price` and `parcels.chargeable_amount` are price snapshots taken at sale time.

## 3. Shipment follow-ups (all append-only or resolve-once)

```mermaid
erDiagram
    shipments ||--o{ shipment_notes : "shipment_id"
    shipments ||--o{ receiver_corrections : "shipment_id"
    shipments ||--o{ incidents : "shipment_id"
    shipments ||--o{ cancellation_requests : "shipment_id"
    stations ||--o{ shipment_notes : "station_id"
    stations ||--o{ receiver_corrections : "station_id"
    stations ||--o{ incidents : "station_id"
    stations ||--o{ cancellation_requests : "station_id"
    users ||--o{ shipment_notes : "created_by_id"
    users ||--o{ receiver_corrections : "created_by_id"
    users ||--o{ incidents : "created_by_id / resolved_by_id"
    users ||--o{ cancellation_requests : "requested_by_id / decided_by_id"

    shipment_notes { uuid id PK
        text body }
    receiver_corrections { uuid id PK
        text name
        text phone
        text reason }
    incidents { uuid id PK
        text kind
        text status
        text note
        text resolution
        ts resolved_at }
    cancellation_requests { uuid id PK
        text reason
        text status
        text decision_reason
        money fee
        money refund_amount
        ts decided_at }
```

## 4. Pricing and settings

```mermaid
erDiagram
    size_classes ||--o{ price_changes : "size_class_id (nullable)"
    sale_items   ||--o{ price_changes : "sale_item_id (nullable)"
    users        ||--o{ price_changes : "changed_by_id"
    stations     |o--o{ setting_changes : "station_id (nullable)"
    users        ||--o{ setting_changes : "changed_by_id"

    size_classes { uuid id PK
        text name_en
        money price
        bool active }
    sale_items { uuid id PK
        text name_en
        money unit_price
        bool active }
    pricing_settings { uuid id PK
        bool singleton UK
        money price_per_kg }
    cancellation_fee_settings { uuid id PK
        bool singleton UK
        bigint percent
        money cap }
    price_changes { uuid id PK
        text kind
        money price }
    setting_changes { uuid id PK
        text kind
        bigint percent
        money cap
        bool requires_approval
        bigint days }
```

`pricing_settings` and `cancellation_fee_settings` are single-row tables (`singleton` unique). Every change to prices or settings also writes a row to `price_changes` / `setting_changes`.

## Notes for the scale-up plan

- **Biggest growth tables:** `shipments`, `status_events`, `payments`, `parcels`, `refresh_tokens`. `refresh_tokens` and `tokens` need an expiry cleanup job; the rest are long-term records.
- **Hot join paths:** station -> shipments (origin and destination), shipment -> status_events, manifest -> shipments. Index these foreign keys and check them with `pgbot`'s `suggest_indexes` on real data.
- **Read replicas later:** reports and list screens read `shipments` + `status_events`; writes stay on the primary.
- **Partitioning candidates later (not now):** `status_events` and `payments` by month, once they are in the tens of millions of rows.
