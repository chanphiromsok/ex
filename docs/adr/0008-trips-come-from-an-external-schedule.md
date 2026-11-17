# Trips come from an external schedule; we keep a Manifest per Trip

Supersedes the "no Bus Trips, no manifest" part of ADR-0002 (the rest of 0002 still holds).

The company already owns the bus schedule in an external service. We do not store Trip master data. A thin adapter (`Ex.Schedule`, one function `departures(route, date)`, called with `Req`, short cache) reads the departures for a Route and a date.

A Shipment gets an optional `external_trip_id` when it is created or later, before the Trip departs. At the same time we copy a snapshot onto it (departure time, bus plate, driver), because the external service can change or delete a Trip and an Invoice or history must not change with it. If the service is down the Shipment is still created, without a Trip.

A **Manifest** is our own record, one per `external_trip_id`, created when the first Shipment is attached. It lists the Shipments on that Trip and records what only we can know: who loaded it, who unloaded it, status (open, departed, arrived), and the missing and unexpected checks on arrival. Departing or arriving a Manifest writes the normal Status Events for each Shipment, so ADR-0001 and ADR-0005 still hold.

Decided for v1: one Shipment goes on exactly one Trip, and the Manifest works at Shipment level (a line shows the Parcel count). Per-Parcel tracking is still rejected, as in ADR-0002.
