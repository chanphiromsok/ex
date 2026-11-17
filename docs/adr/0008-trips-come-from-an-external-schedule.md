# Trips come from an external schedule; we keep a Manifest per Trip

Supersedes the "no Bus Trips, no manifest" part of ADR-0002 (the rest of 0002 still holds).

The company already owns the bus schedule in an external service. We do not store Trip master data. A thin adapter (`Ex.Schedule`, one function `departures(route, date)`, called with `Req`, short cache) reads the departures for a Route and a date.

A **Manifest** is our own record, one per Trip and origin/destination Station pair (`external_trip_id`), opened by origin staff from the schedule. It copies the Trip's departure time, bus label (the bus model) and driver as a snapshot, because the external service can change or delete a Trip and our history must not change with it. A Shipment points at its Manifest with `manifest_id` (null until scanned on). If the service is down a Shipment is still created; only opening a Manifest needs the schedule.

Flow: staff scan each Shipment's Invoice Number onto an open Manifest (origin Station; only Received Shipments on the same Station pair, on no other Manifest). Departing writes In Transit Status Events for every loaded Shipment at once. At the destination Station each scan marks that Shipment Arrived; Shipments never scanned stay In Transit and show as `remaining_count`. All status changes go through the normal Status Events, so ADR-0001 and ADR-0005 still hold.

`Ex.Schedule.Http` is the real client; it is used when `SCHEDULE_URL` (and `SCHEDULE_TOKEN`) are set, otherwise `Ex.Schedule.Mock` answers with four departures a day. The service's Stations are matched to ours by `stations.external_id`, set by an admin. Their trips carry no bus plate or driver, so those stay empty; a trip that has already departed cannot be opened.

Decided for v1: one Shipment goes on exactly one Trip, and the Manifest works at Shipment level (a line shows the Parcel count). Per-Parcel tracking is still rejected, as in ADR-0002.
