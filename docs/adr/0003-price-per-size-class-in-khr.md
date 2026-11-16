# Prices are in KHR: one price per kg, one price per Size Class

All prices and Payments are in KHR with no conversion. For each Parcel staff choose how it is measured: by kg (weight times one global price per kg) or by size (a Size Class with one global price). Prices are not per Route or Station. There is no versioned Price List: a Parcel keeps its own price snapshot, so Admin edits only affect new Shipments. Money fields use ash_money so USD can be added later without a schema change.

Staff choosing the cheaper type is a known risk, accepted for v1; the measurement type is recorded per Parcel so reports can show each staff member's pattern.

Rejected: a versioned Price List with per-Route rates; "higher of weight or size" pricing; Size Classes with weight and dimension limits (too much to enter and maintain).

Rounding: a kg Parcel's Chargeable Amount is weight times price per kg, rounded to whole riel (half up). Every amount is a whole number of riel.

Cancellation Fee: when a Shipment is cancelled the Sender is refunded what they paid minus the fee, where fee = the smaller of (Shipment Total times a global percentage) and a global cap, rounded to whole riel. The percentage and cap are global, set only by an Admin, and each change is logged like a price change.
