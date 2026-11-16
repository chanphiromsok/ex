defmodule ExWeb.HealthControllerTest do
  use ExWeb.ConnCase

  test "GET /health answers 200 when the database is reachable", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert response(conn, 200) == "ok"
  end
end
