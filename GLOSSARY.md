# Express Cargo

Express goods carried by bus between our stations. A sender walks into a station and hands over goods; a receiver collects them at the destination station.

## Language

**Shipment**:
The agreement to carry one Sender's goods from an origin Station to a destination Station. Holds one or more Parcels, one Invoice Number, and the Payments made against it. Moves and is collected as a whole.
_Avoid_: Order, booking, consignment

**Parcel**:
One physical item inside a Shipment, measured by kg or by Size Class, chosen by staff.
_Avoid_: Package, piece, box

**Invoice Number**:
The unique running number of a Shipment, generated on its own, printed on the Invoice and on each Parcel label, and used by staff to find the Shipment.
_Avoid_: Invoice Number, tracking number, ticket

**Invoice**:
The paper given to the Sender showing the Invoice Number, each Parcel's weight or Size Class, and the Shipment Total.
_Avoid_: Receipt

**Station**:
A physical place where staff accept and hand out Parcels. Belongs to a Location.
_Avoid_: Branch, office, terminal

**Location**:
A province or city that contains one or more Stations. Locations, Stations, Size Classes and Sale Items each have an English and a Khmer name.
_Avoid_: City (as a record)

**Station Staff**:
A user who works at one Station and serves walk-in customers. Staff mostly sign in with their phone number; an email is optional. A user needs at least one of the two.
_Avoid_: Agent, clerk, operator

**Supervisor**:
Station Staff who may approve Cancellations at their Station. An Admin may approve a Cancellation at any Station.
_Avoid_: Manager

**Admin**:
A company-wide user who maintains reference data and Station Settings. Has no Station and cannot take Payments, receive, cancel or collect Shipments.
_Avoid_: Super user, manager

**Permission**:
A named thing a user may do, such as creating a Shipment or approving a Cancellation. The list of Permissions is fixed by the application, because code must check each one; which role gets which is data.
_Avoid_: Right, privilege, scope

**Default Permissions**:
The Permissions a user gets from their role when nothing else is set for them. An Admin can change them without a deploy, and every change is recorded.
_Avoid_: Base rights

**Permission Override**:
A setting an Admin makes for one user and one Permission: grant it, deny it, or reset it to the role's default. Every change is recorded. A denied Permission is refused even if the role has it by default.
_Avoid_: Exception, revoke (use deny)

**Sender**:
The person who hands goods over at the origin Station; name and phone on the Shipment, not an account.
_Avoid_: Customer, client, user

**Receiver**:
The person the goods are addressed to; name and phone on the Shipment, not an account.
_Avoid_: Consignee, customer

**Route**:
The ordered origin Location to destination Location pair a Shipment travels on; owns no price of its own.
_Avoid_: Line, leg

**Trip**:
One bus departure on a Route at a time, owned by the external schedule service; we only keep its id and a snapshot (departure time, bus plate, driver) on each Shipment.
_Avoid_: Route, journey

**Manifest**:
Our record for one Trip: the Shipments loaded on it, who loaded and unloaded it, and what is missing or unexpected on arrival. One Manifest per Trip, many Shipments per Manifest.
_Avoid_: Trip sheet, load list

## Lifecycle

**Status Event**:
One recorded change in a Shipment's status (received, in transit, arrived, collected, cancelled), with who made it, where, when (server time), and a reason when required. A Shipment's status is its latest Status Event; events are never edited or deleted.
_Avoid_: Status update, state change

**Received**:
The status of a Shipment once its Payments sum to its Shipment Total at the origin Station.
_Avoid_: Created, booked

**In Transit**:
The status set by the origin Station when the Shipment leaves on a bus.
_Avoid_: Shipped, dispatched

**Arrived**:
The status set by the destination Station when it receives the Shipment.
_Avoid_: Delivered

**Cancellation Fee**:
The part of the Sender's payment kept when a Shipment is cancelled: a percentage of the Shipment Total, never more than a maximum amount. Both values are set globally by an Admin and each change is recorded.
_Avoid_: Penalty, refund fee

**Cancellation**:
A Status Event ending a Shipment before it leaves the origin Station, always with a reason; may need Supervisor (or Admin) approval depending on Station Setting. The approver is never the person who asked. The Sender is refunded what they paid minus the Cancellation Fee.
_Avoid_: Void, delete

**Receiver Correction**:
A recorded replacement of the Receiver's name and phone on a Shipment, added only by a Supervisor at the origin Station with a reason; the latest one is the Receiver. The original is never edited.
_Avoid_: Edit receiver

**Collection**:
The final Status Event where the Receiver or someone on their behalf takes the Parcels at the destination Station, after showing a phone number that matches the Receiver's phone on the Shipment.
_Avoid_: Pickup, delivery

**Overdue Shipment**:
A Shipment that has stayed Arrived longer than the Station's Overdue Threshold without Collection.
_Avoid_: Abandoned, unclaimed

**Incident**:
A recorded problem with a Shipment after departure: Return to Sender, Redirect, Lost or Damaged, with a reason. Resolved by an Admin; compensation is handled outside the system.
_Avoid_: Complaint, claim

**Note**:
Read-only text a Station adds to a Shipment.
_Avoid_: Comment, edit

## Station Settings

**Station Setting**:
A per-Station rule changed only by an Admin, each change recorded. Includes whether Cancellation needs approval and the Overdue Threshold.
_Avoid_: Config, preference

**Overdue Threshold**:
The number of days after which an Arrived Shipment becomes an Overdue Shipment; a Station Setting.
_Avoid_: Grace period

## Payment

**Payment**:
A recorded movement of money against a Shipment, with method and amount; always paid by the Sender. Never edited; a refund is a separate negative Payment, recorded once per cancelled Shipment, against the staff member who took the original Payment.
_Avoid_: Invoice, receipt, transaction

**Shipment Total**:
The price snapshot of a Shipment: the sum of its Parcels' Chargeable Amounts plus its Sale Items, fixed when the Shipment is created.
_Avoid_: Invoice, bill

**Declared Value**:
The value of the goods as stated by the Sender; recorded only and not charged on.
_Avoid_: Insured value, COD amount

## Pricing

**Chargeable Amount**:
The price of one Parcel: its weight times the price per kg, or its Size Class price, depending on how staff measured it.
_Avoid_: Volumetric weight, final weight

**Size Class**:
A named size (for example Small, Medium, Large) with its own price, chosen by staff for a Parcel measured by size.
_Avoid_: Box size, package type

**Sale Item**:
A product sold over the counter, such as a packaging box or plastic bag, charged on the Shipment Total.
_Avoid_: Add-on, extra, packaging fee
