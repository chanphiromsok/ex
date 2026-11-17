defmodule ExWeb.Api.ManifestsTest do
  @moduledoc """
  A Manifest is one bus Trip from the (mock) schedule. Origin staff open it and scan Shipments on, depart it
  (everything becomes In transit); destination staff scan them off (Arrived) and close it.
  """
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  setup %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    pp = station!("PP Central")
    sr = station!("SR Central")
    other = station!("Other")

    for {a, b} <- [{pp, sr}, {pp, other}] do
      Ash.create!(
        Ex.Network.Route,
        %{origin_location_id: a.location_id, destination_location_id: b.location_id},
        authorize?: false
      )
    end

    post(admin, "/api/v1/pricing/price-per-kg", %{
      data: %{
        type: "pricing-setting",
        attributes: %{price_per_kg: %{amount: "1250", currency: "KHR"}}
      }
    })
    |> json_response(201)

    origin = build_conn() |> signed_in(user!(:staff, pp))
    destination = build_conn() |> signed_in(user!(:staff, sr))
    bystander = build_conn() |> signed_in(user!(:staff, station!("Bystander")))

    {:ok, [trip | _]} =
      Ex.Schedule.departures(pp.id, sr.id, Date.utc_today())

    %{
      origin: origin,
      destination: destination,
      bystander: bystander,
      pp: pp,
      sr: sr,
      other: other,
      trip: trip
    }
  end

  defp shipment!(conn, to) do
    conn
    |> post("/api/v1/shipments", %{
      data: %{
        type: "shipment",
        attributes: %{
          idempotency_key: Ecto.UUID.generate(),
          sender_phone: "012 345 678",
          receiver_phone: "097 111 2222",
          destination_station_id: to.id,
          payment_method: "cash",
          parcels: [%{measurement_type: "kg", weight_kg: "1"}]
        }
      }
    })
    |> json_response(201)
    |> get_in(["data", "attributes", "invoice_no"])
  end

  defp open(conn, trip_id, to) do
    post(conn, "/api/v1/manifests", %{
      data: %{
        type: "manifest",
        attributes: %{external_trip_id: trip_id, destination_station_id: to.id}
      }
    })
  end

  defp act(conn, id, step, attrs \\ %{}) do
    patch(conn, "/api/v1/manifests/#{id}/#{step}", %{
      data: %{type: "manifest", id: id, attributes: attrs}
    })
  end

  defp scan(conn, id, invoice_no), do: act(conn, id, "scan", %{invoice_no: invoice_no})

  defp manifest(conn, id),
    do:
      conn
      |> get("/api/v1/manifests/#{id}")
      |> json_response(200)
      |> get_in(["data", "attributes"])

  defp shipment_status(conn, invoice_no) do
    conn
    |> get("/api/v1/shipments?filter[invoice_no]=#{invoice_no}")
    |> json_response(200)
    |> get_in(["data", Access.at(0), "attributes", "status"])
  end

  defp opened(ctx) do
    body = ctx.origin |> open(ctx.trip.trip_id, ctx.sr) |> json_response(201)
    body["data"]["id"]
  end

  test "lists the day's departures from the schedule", ctx do
    body =
      ctx.origin
      |> get(
        "/api/v1/manifests/departures?destination_station_id=#{ctx.sr.id}&date=#{Date.utc_today()}"
      )
      |> json_response(200)

    assert length(body) == 4
    assert ctx.trip.trip_id in Enum.map(body, & &1["trip_id"])
  end

  describe "opening" do
    test "copies the trip snapshot and starts open; opening it again returns the same Manifest",
         ctx do
      body = ctx.origin |> open(ctx.trip.trip_id, ctx.sr) |> json_response(201)
      attrs = body["data"]["attributes"]
      assert attrs["status"] == "open"
      assert attrs["bus_label"] == ctx.trip.bus_label
      assert attrs["origin_station_id"] == ctx.pp.id

      again = ctx.origin |> open(ctx.trip.trip_id, ctx.sr) |> json_response(201)
      assert again["data"]["id"] == body["data"]["id"]
    end

    test "an unknown trip, or a trip on another Route, is refused", ctx do
      assert ctx.origin |> open("nope", ctx.sr) |> json_response(400)
      assert ctx.origin |> open(ctx.trip.trip_id, ctx.other) |> json_response(400)
    end

    test "a Station with no Route to the destination cannot open one", ctx do
      {:ok, [t | _]} =
        Ex.Schedule.departures(ctx.sr.id, ctx.pp.id, Date.utc_today())

      assert ctx.destination |> open(t.trip_id, ctx.pp) |> json_response(400)
    end
  end

  describe "the whole trip" do
    test "load, depart, unload, close", ctx do
      id = opened(ctx)
      a = shipment!(ctx.origin, ctx.sr)
      b = shipment!(ctx.origin, ctx.sr)

      assert ctx.origin |> scan(id, a) |> json_response(200)
      assert ctx.origin |> scan(id, a) |> json_response(200)
      assert ctx.origin |> scan(id, b) |> json_response(200)
      assert manifest(ctx.origin, id)["shipment_count"] == 2

      assert ctx.origin |> act(id, "depart") |> json_response(200)
      assert manifest(ctx.origin, id)["status"] == "departed"
      assert shipment_status(ctx.origin, a) == "in_transit"
      assert shipment_status(ctx.origin, b) == "in_transit"

      assert ctx.destination |> scan(id, a) |> json_response(200)
      assert ctx.destination |> scan(id, a) |> json_response(200)
      m = manifest(ctx.destination, id)
      assert {m["arrived_count"], m["remaining_count"]} == {1, 1}
      assert shipment_status(ctx.destination, a) == "arrived"
      assert shipment_status(ctx.destination, b) == "in_transit"

      assert ctx.destination |> act(id, "arrive") |> json_response(200)
      assert manifest(ctx.destination, id)["status"] == "arrived"
      assert ctx.destination |> scan(id, b) |> json_response(400)
    end
  end

  describe "scan rules" do
    test "unknown Invoice Number, other Station, other Route", ctx do
      id = opened(ctx)
      assert ctx.origin |> scan(id, 999_999_999) |> json_response(400)

      elsewhere = shipment!(ctx.origin, ctx.other)
      assert ctx.origin |> scan(id, elsewhere) |> json_response(400)

      mine = shipment!(ctx.origin, ctx.sr)
      assert ctx.destination |> scan(id, mine) |> json_response(400)
      assert ctx.bystander |> scan(id, mine) |> json_response(404)
    end

    test "a Shipment can be on only one Manifest", ctx do
      id = opened(ctx)

      {:ok, [_, later | _]} =
        Ex.Schedule.departures(ctx.pp.id, ctx.sr.id, Date.utc_today())

      second =
        ctx.origin |> open(later.trip_id, ctx.sr) |> json_response(201) |> get_in(["data", "id"])

      no = shipment!(ctx.origin, ctx.sr)
      assert ctx.origin |> scan(id, no) |> json_response(200)
      assert ctx.origin |> scan(second, no) |> json_response(400)
    end

    test "a loaded Shipment that moved on by itself is dropped at departure", ctx do
      id = opened(ctx)
      kept = shipment!(ctx.origin, ctx.sr)
      moved = shipment!(ctx.origin, ctx.sr)
      assert ctx.origin |> scan(id, kept) |> json_response(200)
      assert ctx.origin |> scan(id, moved) |> json_response(200)

      shipment_id =
        ctx.origin
        |> get("/api/v1/shipments?filter[invoice_no]=#{moved}")
        |> json_response(200)
        |> get_in(["data", Access.at(0), "id"])

      patch(ctx.origin, "/api/v1/shipments/#{shipment_id}/in-transit", %{
        data: %{type: "shipment", id: shipment_id, attributes: %{}}
      })
      |> json_response(200)

      assert ctx.origin |> act(id, "depart") |> json_response(200)
      assert manifest(ctx.origin, id)["shipment_count"] == 1
      assert shipment_status(ctx.origin, kept) == "in_transit"
    end

    test "an empty Manifest cannot depart; only the origin Station departs", ctx do
      id = opened(ctx)
      assert ctx.origin |> act(id, "depart") |> json_response(400)

      no = shipment!(ctx.origin, ctx.sr)
      assert ctx.origin |> scan(id, no) |> json_response(200)
      assert ctx.destination |> act(id, "depart") |> json_response(400)
      assert ctx.origin |> act(id, "arrive") |> json_response(400)
    end

    test "a bystander Station cannot see the Manifest", ctx do
      id = opened(ctx)
      assert ctx.bystander |> get("/api/v1/manifests/#{id}") |> json_response(404)
    end
  end
end
