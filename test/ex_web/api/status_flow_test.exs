defmodule ExWeb.Api.StatusFlowTest do
  @moduledoc """
  A Shipment moves received -> in_transit -> arrived -> collected, in that order, never skipping.
  Origin Station marks In Transit; destination Station marks Arrived and Collected.
  """
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  setup %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    pp_station = station!("PP Central")
    sr_station = station!("SR Central")

    Ash.create!(
      Ex.Network.Route,
      %{
        origin_location_id: pp_station.location_id,
        destination_location_id: sr_station.location_id
      },
      authorize?: false
    )

    post(admin, "/api/v1/pricing/price-per-kg", %{
      data: %{
        type: "pricing-setting",
        attributes: %{price_per_kg: %{amount: "1250", currency: "KHR"}}
      }
    })
    |> json_response(201)

    origin = build_conn() |> signed_in(user!(:staff, pp_station))
    destination = build_conn() |> signed_in(user!(:staff, sr_station))
    other = build_conn() |> signed_in(user!(:staff, station!("Other")))

    id =
      origin
      |> post("/api/v1/shipments", %{
        data: %{
          type: "shipment",
          attributes: %{
            idempotency_key: Ecto.UUID.generate(),
            sender_name: "Sok Dara",
            sender_phone: "012 345 678",
            receiver_name: "Chea Srey",
            receiver_phone: "097 111 2222",
            destination_station_id: sr_station.id,
            payment_method: "cash",
            parcels: [%{measurement_type: "kg", weight_kg: "1"}]
          }
        }
      })
      |> json_response(201)
      |> get_in(["data", "id"])

    %{origin: origin, destination: destination, other: other, id: id}
  end

  defp move(conn, id, step, attrs \\ %{}) do
    patch(conn, "/api/v1/shipments/#{id}/#{step}?include=status_events", %{
      data: %{type: "shipment", id: id, attributes: attrs}
    })
  end

  defp status(conn, id),
    do:
      conn
      |> get("/api/v1/shipments/#{id}")
      |> json_response(200)
      |> get_in(["data", "attributes", "status"])

  describe "the whole journey" do
    test "received, in transit, arrived, collected - each event numbered in order", ctx do
      assert status(ctx.origin, ctx.id) == "received"

      body = ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)
      assert body["data"]["attributes"]["status"] == "in_transit"
      assert body["data"]["attributes"]["status_label_en"] == "In transit"

      body = ctx.destination |> move(ctx.id, "arrived") |> json_response(200)
      assert body["data"]["attributes"]["status"] == "arrived"

      body =
        ctx.destination
        |> move(ctx.id, "collect", %{receiver_phone: "+855 97 111 2222"})
        |> json_response(200)

      assert body["data"]["attributes"]["status"] == "collected"
      assert body["data"]["attributes"]["status_label_km"] == "បានទទួលយកអីវ៉ាន់"

      events =
        body["included"]
        |> Enum.filter(&(&1["type"] == "status-event"))
        |> Enum.sort_by(& &1["attributes"]["seq"])

      assert Enum.map(events, & &1["attributes"]["status"]) ==
               ["received", "in_transit", "arrived", "collected"]

      assert Enum.map(events, & &1["attributes"]["seq"]) == [1, 2, 3, 4]
    end
  end

  describe "status_history" do
    test "lists every step oldest first, with labels, without ?include", ctx do
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)
      ctx.destination |> move(ctx.id, "arrived") |> json_response(200)

      history =
        ctx.origin
        |> get("/api/v1/shipments/#{ctx.id}")
        |> json_response(200)
        |> get_in(["data", "attributes", "status_history"])

      assert Enum.map(history, & &1["status"]) == ["received", "in_transit", "arrived"]
      assert Enum.map(history, & &1["seq"]) == [1, 2, 3]
      assert Enum.map(history, & &1["status_label_en"]) == ["Received", "In transit", "Arrived"]
    end
  end

  describe "nothing can be skipped or repeated" do
    test "received cannot go straight to arrived", ctx do
      assert ctx.destination |> move(ctx.id, "arrived") |> json_response(400)
      assert status(ctx.origin, ctx.id) == "received"
    end

    test "received cannot go straight to collected", ctx do
      assert ctx.destination
             |> move(ctx.id, "collect", %{receiver_phone: "0971112222"})
             |> json_response(400)

      assert status(ctx.origin, ctx.id) == "received"
    end

    test "in transit cannot go straight to collected", ctx do
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)

      assert ctx.destination
             |> move(ctx.id, "collect", %{receiver_phone: "0971112222"})
             |> json_response(400)

      assert status(ctx.origin, ctx.id) == "in_transit"
    end

    test "a step cannot be repeated", ctx do
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)
      assert ctx.origin |> move(ctx.id, "in-transit") |> json_response(400)

      ctx.destination |> move(ctx.id, "arrived") |> json_response(200)
      assert ctx.destination |> move(ctx.id, "arrived") |> json_response(400)
    end

    test "a collected Shipment cannot be collected again", ctx do
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)
      ctx.destination |> move(ctx.id, "arrived") |> json_response(200)

      ctx.destination
      |> move(ctx.id, "collect", %{receiver_phone: "0971112222"})
      |> json_response(200)

      assert ctx.destination
             |> move(ctx.id, "collect", %{receiver_phone: "0971112222"})
             |> json_response(400)
    end
  end

  describe "only the right Station moves it" do
    test "the destination cannot mark In Transit", ctx do
      assert ctx.destination |> move(ctx.id, "in-transit") |> response(403)
    end

    test "the origin cannot mark Arrived", ctx do
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)
      assert ctx.origin |> move(ctx.id, "arrived") |> response(403)
    end

    test "a third Station can do neither", ctx do
      assert ctx.other |> move(ctx.id, "in-transit") |> response(403)
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)
      assert ctx.other |> move(ctx.id, "arrived") |> response(403)
    end

    test "only the destination collects, and only with the Receiver's phone", ctx do
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)
      ctx.destination |> move(ctx.id, "arrived") |> json_response(200)

      assert ctx.origin
             |> move(ctx.id, "collect", %{receiver_phone: "0971112222"})
             |> response(403)

      assert ctx.destination
             |> move(ctx.id, "collect", %{receiver_phone: "012999888"})
             |> json_response(400)

      assert ctx.destination |> move(ctx.id, "collect", %{}) |> json_response(400)
      assert status(ctx.origin, ctx.id) == "arrived"
    end
  end

  describe "the event records where it happened" do
    test "each event has the Station of the user who recorded it", ctx do
      ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)

      body =
        ctx.origin
        |> get("/api/v1/shipments/#{ctx.id}?include=status_events")
        |> json_response(200)

      stations =
        for e <- body["included"], do: {e["attributes"]["status"], e["attributes"]["station_id"]}

      assert length(stations) == 2
      assert stations |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1
    end
  end

  describe "at the same time" do
    test "two simultaneous In Transit requests make one event", ctx do
      results =
        1..4
        |> Task.async_stream(
          fn _ -> ctx.origin |> move(ctx.id, "in-transit") |> Map.get(:status) end,
          max_concurrency: 4,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, s} -> s end)

      assert Enum.count(results, &(&1 == 200)) == 1
      assert Enum.all?(results, &(&1 in [200, 400]))

      body =
        ctx.origin
        |> get("/api/v1/shipments/#{ctx.id}?include=status_events")
        |> json_response(200)

      assert length(body["included"]) == 2
    end
  end
end
