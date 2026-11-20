defmodule ExWeb.NotFoundTest do
  use ExWeb.ConnCase, async: true

  test "GET / is a 404 with a JSON error body", %{conn: conn} do
    conn = conn |> put_req_header("accept", "application/json") |> get("/")
    assert %{"errors" => %{"detail" => "Not Found"}} = json_response(conn, 404)
  end
end
