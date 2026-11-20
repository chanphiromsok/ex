defmodule ExWeb.Plugs.ApiDocsTest do
  use ExWeb.ConnCase, async: false

  test "docs and spec are served when enabled", %{conn: conn} do
    assert get(conn, "/api/docs").status == 200
    assert get(conn, "/api/v1/open_api").status == 200
  end

  test "docs and spec answer 404 when disabled", %{conn: conn} do
    Application.put_env(:ex, :api_docs, false)
    on_exit(fn -> Application.put_env(:ex, :api_docs, true) end)

    assert get(conn, "/api/docs").status == 404
    assert get(conn, "/api/v1/open_api").status == 404
  end
end
