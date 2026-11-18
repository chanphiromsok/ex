import Config

config :ex, token_signing_secret: "OJYtU5iFycDQ4I7gXg8LZO/7/1rVi6pO"
config :bcrypt_elixir, log_rounds: 1

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "UVu6kZKX4IPf/Q2vCfnN8HwXR6W+i4lcZqVFerl02XU",
  disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ex, Ex.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ex_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex, ExWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "50Q0Ddkphtz1wRolforEKbR8on6+NnYQ5x0qFjlUvK7xXTzTMuIeQtTqnpJHLwcC",
  server: false


# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Rate limiting is off in tests; test/ex_web/plugs/rate_limit_test.exs turns it on explicitly.
config :ex, ExWeb.Plugs.RateLimit, enabled: false
