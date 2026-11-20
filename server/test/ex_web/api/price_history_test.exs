defmodule ExWeb.Api.PriceHistoryTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp khr(amount), do: %{amount: to_string(amount), currency: "KHR"}

  defp create_size_class(admin, price) do
    admin
    |> post("/api/v1/size-classes", %{
      data: %{
        type: "size-class",
        attributes: %{name_en: "Box", name_km: "ប្រអប់", price: khr(price)}
      }
    })
    |> json_response(201)
  end

  defp set_price(admin, id, price) do
    patch(admin, "/api/v1/size-classes/#{id}/price", %{
      data: %{type: "size-class", id: id, attributes: %{price: khr(price)}}
    })
  end

  test "every price set is recorded with who set it, oldest first", %{conn: conn} do
    user = user!(:admin)
    admin = conn |> signed_in(user)
    id = create_size_class(admin, 5000)["data"]["id"]
    assert set_price(admin, id, 6500) |> json_response(200)

    history = admin |> get("/api/v1/price-changes?sort=inserted_at") |> json_response(200)

    assert [first, second] = history["data"]
    assert first["attributes"]["kind"] == "size_class"
    assert first["attributes"]["price"] == %{"amount" => "5000", "currency" => "KHR"}
    assert second["attributes"]["price"] == %{"amount" => "6500", "currency" => "KHR"}
    assert second["attributes"]["size_class_id"] == id
    assert second["attributes"]["changed_by_id"] == user.id
  end

  test "setting a price changes only that Size Class", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    id = create_size_class(admin, 5000)["data"]["id"]
    set_price(admin, id, 7000) |> json_response(200)

    shown = admin |> get("/api/v1/size-classes/#{id}") |> json_response(200)
    assert shown["data"]["attributes"]["price"]["amount"] == "7000"
  end

  test "a price that is not positive whole KHR is refused and not logged", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    id = create_size_class(admin, 5000)["data"]["id"]

    assert set_price(admin, id, "12.5") |> json_response(400)

    assert [_only_the_first] =
             admin |> get("/api/v1/price-changes") |> json_response(200) |> Map.fetch!("data")
  end

  test "staff cannot set a price and see no history", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    id = create_size_class(admin, 5000)["data"]["id"]
    staff = build_conn() |> signed_in(user!(:staff))

    assert set_price(staff, id, 1) |> json_response(403)
    assert %{"data" => []} = staff |> get("/api/v1/price-changes") |> json_response(200)
  end

  test "the history cannot be edited or deleted through the API", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    create_size_class(admin, 5000)
    [change] = admin |> get("/api/v1/price-changes") |> json_response(200) |> Map.fetch!("data")

    assert admin |> delete("/api/v1/price-changes/#{change["id"]}") |> json_response(404)
  end
end
