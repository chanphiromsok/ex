defmodule ExWeb.Plugs.ApiDocs do
  @moduledoc """
  Serves the Scalar page at `/api/docs` and lets `/api/v1/open_api` through, but only when
  `config :ex, :api_docs` is true. Off, both answer 404, so a public server does not publish
  the full API map. On by default; `config/runtime.exs` sets it from `API_DOCS` in prod.

  The flag is read per request: endpoint plugs are initialised at compile time in prod.
  """
  import Plug.Conn

  @docs_path "/api/docs"
  @spec_path "/api/v1/open_api"

  def init(_opts) do
    ScalarPlug.init(path: @docs_path, spec_href: @spec_path, title: "API Documentation")
  end

  def call(%{request_path: path} = conn, scalar) when path in [@docs_path, @spec_path] do
    cond do
      not Application.get_env(:ex, :api_docs, true) -> conn |> send_resp(404, "") |> halt()
      path == @docs_path -> ScalarPlug.call(conn, scalar)
      true -> conn
    end
  end

  def call(conn, _scalar), do: conn
end
