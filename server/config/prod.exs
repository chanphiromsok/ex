import Config

# Force using SSL in production. This also sets the "strict-security-transport" header,
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :ex, ExWeb.Endpoint,
  # TEMPORARY: accept websocket origins from the droplet IP (ops dashboard). Remove with the IP above.
  check_origin: ["//localhost", "//159.223.95.98"],
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      paths: ["/health"],
      # TEMPORARY: droplet IP allowed over plain HTTP until the domain is active. Remove afterwards.
      hosts: ["localhost", "127.0.0.1", "159.223.95.98"]
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
