# Append-only tables are enforced in Postgres as well as Ash

Payments, Status Events, Notes and the change-log tables (Station Setting changes, user assignment changes) have no update or destroy action in Ash, and a Postgres trigger rejects UPDATE and DELETE on them. Incidents and cancellation requests allow only a resolve or decide update on their own columns.

All event timestamps are set by the server in UTC; staff cannot supply a time. Reports convert to Asia/Phnom_Penh.

Parcels and Sale Item lines are created in the same transaction as the Shipment and its first Payment, and are immutable once the Shipment is Received.

Rejected: Ash-level rules only. Anyone with database access could still edit cash records.

Ash: this is enforced both by the resource (no update/destroy action) and by a `custom_statements` trigger in the generated migration. See docs/schema.md.
