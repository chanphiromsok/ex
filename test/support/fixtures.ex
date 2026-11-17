defmodule Ex.Fixtures do
  @moduledoc "Test helpers: create reference data and users, and sign in through the API."
  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint ExWeb.Endpoint

  def location!(name \\ "Phnom Penh") do
    Ash.create!(Ex.Network.Location, %{name_en: name, name_km: "km " <> name}, authorize?: false)
  end

  def station!(name \\ "PP Central") do
    location = location!("Loc " <> name)

    Ash.create!(
      Ex.Network.Station,
      %{name_en: name, name_km: "km " <> name, location_id: location.id},
      authorize?: false
    )
  end

  def user!(role, station \\ nil) do
    station = if role == :admin, do: nil, else: station || station!("S " <> Ecto.UUID.generate())

    Ash.create!(
      Ex.Accounts.User,
      %{
        email: "#{role}-#{System.unique_integer([:positive])}@example.com",
        password: "password123",
        password_confirmation: "password123",
        role: role,
        station_id: station && station.id
      },
      action: :register_with_password,
      authorize?: false
    )
  end

  @doc "Posts to the JSON:API sign-in route and returns the response conn."
  def sign_in(conn, email, password) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("content-type", "application/vnd.api+json")
    |> post("/api/v1/users/sign-in", %{
      data: %{type: "user", attributes: %{email: to_string(email), password: password}}
    })
  end

  @doc "Signs in through POST /api/v1/users/sign-in and returns a conn carrying the bearer token."
  def signed_in(conn, user) do
    token =
      conn
      |> sign_in(user.email, "password123")
      |> json_response(201)
      |> get_in(["meta", "token"])

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("content-type", "application/vnd.api+json")
  end
end
