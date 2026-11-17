defmodule ExWeb.Api.RefreshTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp json_conn(conn) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("content-type", "application/vnd.api+json")
  end

  defp sign_in(conn, user) do
    json_conn(conn)
    |> post("/api/v1/users/sign-in", %{
      data: %{
        type: "user",
        attributes: %{email: to_string(user.email), password: "password123"}
      }
    })
    |> json_response(201)
    |> Map.fetch!("meta")
  end

  defp refresh(conn, secret) do
    post(json_conn(conn), "/api/v1/users/refresh", %{
      data: %{type: "user", attributes: %{refresh_token: secret}}
    })
  end

  test "sign-in returns an access token and a refresh token", %{conn: conn} do
    meta = sign_in(conn, user!(:staff))
    assert is_binary(meta["token"])
    assert is_binary(meta["refresh_token"])
  end

  test "a refresh token is exchanged for a new pair, and the new access token works", %{
    conn: conn
  } do
    admin = user!(:admin)
    old = sign_in(conn, admin)

    body = refresh(conn, old["refresh_token"]) |> json_response(201)
    assert body["data"]["id"] == admin.id
    new = body["meta"]
    assert new["refresh_token"] != old["refresh_token"]

    assert conn
           |> json_conn()
           |> put_req_header("authorization", "Bearer " <> new["token"])
           |> get("/api/v1/users")
           |> json_response(200)
  end

  test "a refresh token works once; replaying it revokes the whole family", %{conn: conn} do
    old = sign_in(conn, user!(:staff))
    new = refresh(conn, old["refresh_token"]) |> json_response(201) |> Map.fetch!("meta")

    assert refresh(conn, old["refresh_token"]).status in [401, 403]
    assert refresh(conn, new["refresh_token"]).status in [401, 403]
  end

  test "an unknown refresh token is refused", %{conn: conn} do
    assert refresh(conn, "nope").status in [401, 403]
  end
end
