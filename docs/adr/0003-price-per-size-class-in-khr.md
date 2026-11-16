# Prices are in KHR, one price per Size Class

All prices and Payments are in KHR with no conversion. Each Size Class has one global price (not per Route or Station); a Parcel is charged the smallest Size Class its weight and dimensions fit. There is no versioned Price List: a Shipment keeps its own price snapshot, so Admin edits only affect new Shipments. Money fields use ash_money so USD can be added later without a schema change.

Rejected: a versioned Price List with per-kg and per-Route rates and a "higher of weight or size" rule, as too complex for v1. Per-Route pricing can be added later as a separate table.
