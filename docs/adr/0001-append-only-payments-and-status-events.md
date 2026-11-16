# Payments and Status Events are append-only

Station Staff handle cash and could pocket the difference by editing or cancelling a paid Shipment. We record Payments and Status Events as immutable rows (refunds are negative Payments, cancellations are Status Events with a reason) instead of keeping mutable `status` / `paid` fields.

Rejected: mutable fields plus an audit log. A log records tampering after the fact; a ledger makes the cash total derivable and edits impossible.

A Shipment is Received only when its Payments sum to its Shipment Total. No Shipment field is mutable after Received; changes are events.

## Consequences

Status and balance are derived (query or projection). Corrections mean cancel and create a new Shipment. Payments are always from the Sender; there is no payer column (COD is out of scope for good).
