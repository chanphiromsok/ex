defmodule ExWeb.OpsRouter do
  @moduledoc """
  Operator-only pages: LiveDashboard (all environments).

  Mounted last by `ExWeb.Router`. Served under `/dev` in development and `/ops` elsewhere.
  Outside dev the pages sit behind HTTP basic auth (`DASHBOARD_USER` / `DASHBOARD_PASSWORD`);
  if those are not set the pages answer 404.
  """
  use Phoenix.Router, helpers: false

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveDashboard.Router

  @dev? Mix.env() == :dev
  @prefix if @dev?, do: "/dev", else: "/ops"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :basic_auth
  end

  scope @prefix do
    pipe_through :browser

    live_dashboard "/dashboard", metrics: ExWeb.Telemetry
  end

  if @dev? do
    defp basic_auth(conn, _opts), do: conn
  else
    defp basic_auth(conn, _opts) do
      user = System.get_env("DASHBOARD_USER")
      password = System.get_env("DASHBOARD_PASSWORD")

      if user in [nil, ""] or password in [nil, ""] do
        conn |> send_resp(404, "Not Found") |> halt()
      else
        Plug.BasicAuth.basic_auth(conn, username: user, password: password, realm: "Ops")
      end
    end
  end
end
