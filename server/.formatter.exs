[
  import_deps: [
    :ash_authentication,
    :ash_ai,
    :ash_postgres,
    :ash_json_api,
    :ash_phoenix,
    :ash_rate_limiter,
    :ash,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"]
]
