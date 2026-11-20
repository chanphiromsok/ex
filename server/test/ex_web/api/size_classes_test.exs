defmodule ExWeb.Api.SizeClassesTest do
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  @price %{amount: "5000", currency: "KHR"}

  defp create_body(attrs) do
    %{
      data: %{
        type: "size-class",
        attributes: Map.merge(%{name_en: "Small", name_km: "តូច", price: @price}, attrs)
      }
    }
  end

  defp names(conn),
    do:
      conn |> json_response(200) |> Map.fetch!("data") |> Enum.map(& &1["attributes"]["name_en"])

  test "an admin creates a Size Class with a KHR price", %{conn: conn} do
    body =
      conn
      |> signed_in(user!(:admin))
      |> post("/api/v1/size-classes", create_body(%{}))
      |> json_response(201)

    assert body["data"]["attributes"]["name_en"] == "Small"
    assert body["data"]["attributes"]["price"] == %{"amount" => "5000", "currency" => "KHR"}
  end

  test "staff cannot create one", %{conn: conn} do
    conn = conn |> signed_in(user!(:staff)) |> post("/api/v1/size-classes", create_body(%{}))
    assert json_response(conn, 403)
  end

  test "both names are required", %{conn: conn} do
    conn =
      conn
      |> signed_in(user!(:admin))
      |> post("/api/v1/size-classes", create_body(%{name_km: nil}))

    assert json_response(conn, 400)
  end

  test "a price must be a positive whole number of riel in KHR", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))

    for bad <- [
          %{amount: "0", currency: "KHR"},
          %{amount: "1500.5", currency: "KHR"},
          %{amount: "5", currency: "USD"}
        ] do
      assert admin
             |> post("/api/v1/size-classes", create_body(%{price: bad}))
             |> json_response(400)
    end
  end

  test "staff only see active Size Classes, an admin sees all", %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))

    admin
    |> post("/api/v1/size-classes", create_body(%{name_en: "Active One", name_km: "ក"}))
    |> json_response(201)

    inactive =
      admin
      |> post("/api/v1/size-classes", create_body(%{name_en: "Retired", name_km: "ខ"}))
      |> json_response(201)

    admin
    |> patch("/api/v1/size-classes/#{inactive["data"]["id"]}", %{
      data: %{type: "size-class", id: inactive["data"]["id"], attributes: %{active: false}}
    })
    |> json_response(200)

    assert admin |> get("/api/v1/size-classes") |> names() |> Enum.sort() == [
             "Active One",
             "Retired"
           ]

    assert conn |> signed_in(user!(:staff)) |> get("/api/v1/size-classes") |> names() == [
             "Active One"
           ]
  end
end
