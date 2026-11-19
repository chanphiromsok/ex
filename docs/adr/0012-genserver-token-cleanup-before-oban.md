# A GenServer cleans up refresh tokens; Oban waits for the first retryable job

`AshAuthentication.Supervisor` already runs and removes expired rows from `tokens`. Only the custom `refresh_tokens` table needs cleanup. A small periodic GenServer runs one idempotent `DELETE` of expired rows; running it on several nodes at once is harmless, so it still works when a second API node arrives.

Oban (via AshOban) comes in with the first job that needs retries, persistence or scheduling guarantees, for example SMS or Telegram notifications. It is Postgres-backed, so it adds no infrastructure.

Redis is not needed for jobs. It arrives with the second API node, as the shared backend for Hammer rate-limit counters (ETS counters are per node).

Rejected: adding Oban now for a single cleanup query (a dependency, migrations and a supervision tree for work that cannot fail in a way worth retrying).
