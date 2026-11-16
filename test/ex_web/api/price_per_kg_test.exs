defmodule ExWeb.Api.PricePerKgTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp khr(amount), do: %{amount: to_string(amount), currency: "KHR"}

  defp set(conn, amount) do
    post(conn, "/api/v1/pricing/price-per-kg", %{
      data: %{type: "pricing-setting", attributes: %{price_per_kg: khr(amount)}}
    })
  end

  defp current(conn), do: get(conn, "/api/v1/pricing/current")

  test "an admin sets the price per kg and staff can read it", %{conn: conn} do
    set(conn |> signed_in(user!(:admin)), 4000) |> json_response(201)

    shown = build_conn() |> signed_in(user!(:staff)) |> current() |> json_response(200)

    assert shown["data"]["attributes"]["price_per_kg"] == %{
             "amount" => "4000",
             "currency" => "KHR"
           }
  end

  test "setting it again replaces the one global price and logs both", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    set(admin, 4000) |> json_response(201)
    set(admin, 4500) |> json_response(201)

    assert admin
           |> current()
           |> json_response(200)
           |> get_in(["data", "attributes", "price_per_kg", "amount"]) == "4500"

    history =
      admin
      |> get("/api/v1/price-changes?sort=inserted_at&filter[kind]=price_per_kg")
      |> json_response(200)

    assert Enum.map(history["data"], & &1["attributes"]["price"]["amount"]) == ["4000", "4500"]
  end

  test "there is no price until an admin sets one", %{conn: conn} do
    assert conn |> signed_in(user!(:staff)) |> current() |> json_response(404)
  end

  test "staff cannot set it", %{conn: conn} do
    assert conn |> signed_in(user!(:staff)) |> set(1000) |> json_response(403)
  end

  test "it must be a positive whole number of riel", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    assert admin |> set(0) |> json_response(400)
    assert admin |> set("10.5") |> json_response(400)
  end
end
