defmodule ExWeb.Api.ShipmentListTest do
  @moduledoc """
  `GET /shipments` returns one page at a time, newest first, with a cursor in `links.next`,
  and narrows by `search` (Invoice Number, name or phone).
  """
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  setup %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    pp = station!("PP Central")
    sr = station!("SR Central")

    Ash.create!(
      Ex.Network.Route,
      %{origin_location_id: pp.location_id, destination_location_id: sr.location_id},
      authorize?: false
    )

    post(admin, "/api/v1/pricing/price-per-kg", %{
      data: %{
        type: "pricing-setting",
        attributes: %{price_per_kg: %{amount: "1250", currency: "KHR"}}
      }
    })
    |> json_response(201)

    staff = build_conn() |> signed_in(user!(:staff, pp))

    shipments =
      for {sender, phone} <- [
            {"Sok Dara", "012 345 678"},
            {"Chea Srey", "097 111 2222"},
            {"Lim Vanna", "088 999 0000"}
          ] do
        staff
        |> post("/api/v1/shipments", %{
          data: %{
            type: "shipment",
            attributes: %{
              idempotency_key: Ecto.UUID.generate(),
              sender_name: sender,
              sender_phone: phone,
              receiver_name: "Keo Mony",
              receiver_phone: "010 222 333",
              destination_station_id: sr.id,
              payment_method: "cash",
              parcels: [%{measurement_type: "kg", weight_kg: "1"}]
            }
          }
        })
        |> json_response(201)
        |> Map.fetch!("data")
      end

    %{staff: staff, shipments: shipments}
  end

  defp list(conn, query), do: conn |> get("/api/v1/shipments?" <> query) |> json_response(200)
  defp ids(body), do: Enum.map(body["data"], & &1["id"])

  test "pages newest first and follows the cursor to the end", %{staff: staff, shipments: s} do
    [oldest, middle, newest] = Enum.map(s, & &1["id"])

    first = list(staff, "page[limit]=2")
    assert ids(first) == [newest, middle]
    assert next = first["links"]["next"]

    [_, query] = String.split(next, "?", parts: 2)
    second = list(staff, query)
    assert ids(second) == [oldest]
    assert second["links"]["next"] == nil
  end

  test "without page parameters it still returns a single page", %{staff: staff} do
    body = list(staff, "")
    assert length(body["data"]) == 3
    assert Map.has_key?(body["links"], "next")
  end

  test "search matches a name, a local phone number or an Invoice Number", %{
    staff: staff,
    shipments: [dara, _srey, vanna]
  } do
    assert ids(list(staff, "search=dara")) == [dara["id"]]
    assert ids(list(staff, "search=088%20999")) == [vanna["id"]]
    assert ids(list(staff, "search=%23#{dara["attributes"]["invoice_no"]}")) == [dara["id"]]
    assert list(staff, "search=nobody")["data"] == []
  end

  test "the next-page link keeps the search and filters", %{staff: staff, shipments: s} do
    [oldest | _] = Enum.map(s, & &1["id"])
    first = list(staff, "search=keo&filter[status][in][]=received&page[limit]=2")
    assert length(first["data"]) == 2

    [_, query] = String.split(first["links"]["next"], "?", parts: 2)
    assert ids(list(staff, query)) == [oldest]
  end
end
