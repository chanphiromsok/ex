# Permissions: role defaults in code, per-user overrides as data

Status: superseded by ADR-0007 (role defaults moved from code to tables).

Every action is guarded by a named Permission, not a role name. A role gives Default Permissions, fixed in code. An Admin can override any Permission for one user: grant it, deny it, or reset it to the default. Overrides are an append-only log (`user_permission_changes`); the current override is the latest row per user and Permission. A deny wins over the role default.

The Station rule is separate: a Permission says what a user may do, their Station says where. Permissions that act on a Shipment, Payment or Cancellation need a Station, so they cannot be granted to an Admin, who has none.

Guards: the last Admin who can manage users cannot be denied `user.manage`, and an Admin cannot change their own overrides, so nobody can lock the company out or grant themselves cash access.

Rejected: roles only (a new need means a new role and a deploy); extras that can only add (a Station could not stop one person from, for example, refunding); editable role tables (permissions would no longer be one fixed list tied to code). Overrides are always visible in the log.
