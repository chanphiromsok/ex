# Permissions: role defaults and per-user overrides as data

Supersedes ADR-0006.

Every action is guarded by a named Permission, not a role name. Which Permissions each role gets by default is data, not code: an Admin can change it without a deploy. The tables are `permissions` (one row per Permission the application can check, with whether it is Station-bound), `role_permissions` (a role holds a Permission by default) and, in later tickets, `user_permissions` (a grant or deny for one user) and an append-only `permission_changes` log.

The list of Permissions itself is still fixed by the application, because code has to check each one. The rows come from migrations, and a test fails if they differ from the names in code.

A user's effective Permissions are computed in SQL: the role's default rows, minus Station-bound Permissions when the user has no Station. They are loaded with the user at sign-in and on every request. A Station-bound Permission (acting on a Shipment, Payment or Cancellation at a Station) is therefore never effective for an Admin, even if a role row grants it.

Rejected: role defaults in code (ADR-0006: any change to a default needs a deploy); custom roles (users have exactly three roles, which keeps the Station rule simple).
