defmodule ExWeb.Plugs.RateLimit do
  @moduledoc """
  Fixed-window rate limit per client IP. Sign-in and token refresh get a much tighter budget than
  the rest of the API, to slow password guessing.

  Behind the load balancer the client address is the last `x-forwarded-for` entry (the one the
  balancer appended); without that header we fall back to the socket address.

  Limits come from `config :ex, ExWeb.Plugs.RateLimit` (`:enabled`, `:limit`, `:auth_limit`,
  `:window_ms`) and answer 429 with a `retry-after` header.
  """
  import Plug.Conn

  @auth_suffixes ["/users/sign-in", "/users/refresh"]
  @defaults [enabled: true, limit: 300, auth_limit: 10, window_ms: 60_000]

  def init(opts), do: opts

  def call(conn, _opts) do
    cfg = Keyword.merge(@defaults, Application.get_env(:ex, __MODULE__, []))

    if cfg[:enabled], do: check(conn, cfg), else: conn
  end

  defp check(conn, cfg) do
    {bucket, limit} =
      if auth?(conn.request_path), do: {"auth", cfg[:auth_limit]}, else: {"api", cfg[:limit]}

    case Ex.RateLimit.hit("#{bucket}:#{client_ip(conn)}", cfg[:window_ms], limit) do
      {:allow, _count} -> conn
      {:deny, retry_ms} -> deny(conn, retry_ms)
    end
  end

  defp auth?(path), do: Enum.any?(@auth_suffixes, &String.ends_with?(path, &1))

  defp client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [value | _] -> value |> String.split(",") |> List.last() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp deny(conn, retry_ms) do
    seconds = max(div(retry_ms, 1000), 1)

    body =
      Jason.encode!(%{
        errors: [
          %{
            status: "429",
            code: "rate_limited",
            title: "Too Many Requests",
            detail: "Too many requests. Retry in #{seconds}s."
          }
        ],
        jsonapi: %{version: "1.0"}
      })

    conn
    |> put_resp_header("retry-after", Integer.to_string(seconds))
    |> put_resp_content_type("application/vnd.api+json")
    |> send_resp(429, body)
    |> halt()
  end
end
