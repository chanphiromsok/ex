defmodule ExWeb.HealthController do
  @moduledoc "Readiness probe for the load balancer: 200 when the database answers, 503 otherwise."
  use ExWeb, :controller

  def show(conn, _params) do
    case Ecto.Adapters.SQL.query(Ex.Repo, "SELECT 1", []) do
      {:ok, _} -> send_resp(conn, 200, "ok")
      {:error, _} -> send_resp(conn, 503, "database unavailable")
    end
  end
end
