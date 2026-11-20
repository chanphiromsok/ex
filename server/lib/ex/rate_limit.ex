defmodule Ex.RateLimit do
  @moduledoc "In-memory (ETS) rate limiter. Counters are per node, which is fine for a single instance."
  use Hammer, backend: :ets
end
