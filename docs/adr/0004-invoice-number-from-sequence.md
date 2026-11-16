# Invoice Number comes from its own database sequence

Each Shipment gets an Invoice Number from an identity sequence on `shipments`: a plain running number, unique and safe when two staff save at once, with no counter table or locking. Gaps are acceptable (a rolled-back save or a cancelled Shipment leaves one), cancelled numbers are never reused, and there is no offline mode.

Rejected: `EX-[Date]-[SEQ]` with a daily reset. It needed a locked per-day counter table, and the Sender does not need a dated number. The number is guessable, so Collection also needs a Collection Code or an ID check.
