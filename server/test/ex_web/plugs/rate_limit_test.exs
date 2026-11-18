defmodule ExWeb.Plugs.RateLimitTest do
  use ExWeb.ConnCase, async: false

  setup do
    Application.put_env(:ex, ExWeb.Plugs.RateLimit,
      enabled: true,
      limit: 3,
      auth_limit: 2,
      window_ms: 60_000
    )

    on_exit(fn -> Application.put_env(:ex, ExWeb.Plugs.RateLimit, enabled: false) end)
    %{ip: "10.0.0.#{System.unique_integer([:positive])}"}
  end

  defp from(conn, ip), do: Plug.Conn.put_req_header(conn, "x-forwarded-for", "1.1.1.1, " <> ip)

  test "answers 429 with retry-after once the API budget is spent", %{conn: conn, ip: ip} do
    for _ <- 1..3, do: assert(get(from(conn, ip), "/api/v1/open_api").status != 429)

    conn = get(from(conn, ip), "/api/v1/open_api")
    assert conn.status == 429
    assert [secs] = get_resp_header(conn, "retry-after")
    assert String.to_integer(secs) >= 1
    assert %{"errors" => [%{"code" => "rate_limited"}]} = Jason.decode!(conn.resp_body)
  end

  test "sign-in has its own tighter budget", %{conn: conn, ip: ip} do
    for _ <- 1..2, do: assert(post(from(conn, ip), "/api/v1/users/sign-in", %{}).status != 429)
    assert post(from(conn, ip), "/api/v1/users/sign-in", %{}).status == 429
  end

  test "other clients are not affected", %{conn: conn, ip: ip} do
    for _ <- 1..4, do: get(from(conn, ip), "/api/v1/open_api")
    assert get(from(conn, ip <> "9"), "/api/v1/open_api").status != 429
  end

  describe "sign-in per account" do
    defp bad_sign_in(conn, login) do
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/v1/users/sign-in", %{
        data: %{type: "user", attributes: %{login: login, password: "wrong-password"}}
      })
    end

    test "locks one login after 5 attempts, even from different IPs", %{conn: conn} do
      login = "nobody#{System.unique_integer([:positive])}@example.com"

      for n <- 1..5 do
        refute bad_sign_in(from(conn, "10.1.0.#{n}"), login).status == 429
      end

      assert bad_sign_in(from(conn, "10.1.0.99"), login).status == 429
      refute bad_sign_in(from(conn, "10.1.0.99"), "other@example.com").status == 429
    end
  end
end
