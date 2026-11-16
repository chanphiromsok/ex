# A Shipment holds many Parcels, moves as a whole, and references Stations

One Shipment (one Invoice Number) holds one or more Parcels; status is per Shipment and staff must not split it. Per-Parcel status was rejected for v1 as harder to reverse; revisit with Bus Trips. Origin and destination are Stations belonging to a Location, so cities can later have several Stations.

Bus Trips are left out of v1, so there is no manifest: the origin Station records In Transit and the destination records Arrived. A Parcel lost between Stations is detected only by a missing Arrived event.
