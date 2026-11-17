defmodule ExWeb.Plugs.RequireActor do
  @moduledoc """
  Answers 401 when a request has no valid bearer token, so clients can tell "not signed in" from
  "nothing to show". Sign-in, token refresh and the API docs stay open.
  """
  import Plug.Conn

  @open_suffixes ["/users/sign-in", "/users/refresh", "/open_api"]

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] || open?(conn.request_path) do
      conn
    else
      body =
        Jason.encode!(%{
          errors: [
            %{
              status: "401",
              code: "unauthorized",
              title: "Unauthorized",
              detail: "Sign in and send `Authorization: Bearer <token>`."
            }
          ],
          jsonapi: %{version: "1.0"}
        })

      conn
      |> put_resp_content_type("application/vnd.api+json")
      |> send_resp(401, body)
      |> halt()
    end
  end

  defp open?(path), do: Enum.any?(@open_suffixes, &String.ends_with?(path, &1))
end
