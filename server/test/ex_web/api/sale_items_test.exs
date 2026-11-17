defmodule ExWeb.Api.SaleItemsTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp khr(amount), do: %{amount: to_string(amount), currency: "KHR"}

  defp create(conn, attrs \\ %{}) do
    post(conn, "/api/v1/sale-items", %{
      data: %{
        type: "sale-item",
        attributes: Map.merge(%{name_en: "Tape", name_km: "ក្រដាសបិទ", unit_price: khr(1000)}, attrs)
      }
    })
  end

  test "an admin creates a Sale Item and the creation is logged", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    created = admin |> create() |> json_response(201)
    assert created["data"]["attributes"]["unit_price"]["amount"] == "1000"

    [change] = admin |> get("/api/v1/price-changes") |> json_response(200) |> Map.fetch!("data")
    assert change["attributes"]["kind"] == "sale_item"
    assert change["attributes"]["sale_item_id"] == created["data"]["id"]
  end

  test "an admin sets a new unit price", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    id = admin |> create() |> json_response(201) |> get_in(["data", "id"])

    updated =
      admin
      |> patch("/api/v1/sale-items/#{id}/price", %{
        data: %{type: "sale-item", id: id, attributes: %{unit_price: khr(1500)}}
      })
      |> json_response(200)

    assert updated["data"]["attributes"]["unit_price"]["amount"] == "1500"
  end

  test "staff read active Sale Items but cannot create", %{conn: conn} do
    create(conn |> signed_in(user!(:admin))) |> json_response(201)
    staff = build_conn() |> signed_in(user!(:staff))

    assert [_one] = staff |> get("/api/v1/sale-items") |> json_response(200) |> Map.fetch!("data")
    assert staff |> create(%{name_en: "Other", name_km: "ផ្សេង"}) |> json_response(403)
  end

  test "both names are required and the unit price must be positive whole KHR", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    assert admin |> create(%{name_km: nil}) |> json_response(400)
    assert admin |> create(%{unit_price: khr(0)}) |> json_response(400)
  end
end
