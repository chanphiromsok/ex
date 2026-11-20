defmodule ExWeb.Api.IncidentsOverdueTest do
  @moduledoc """
  Incidents are reported after departure and resolved by an Admin; Overdue Shipments are Arrived ones
  waiting longer than the destination Station's own Overdue Threshold (in days).
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
        attributes: %{price_per_kg: %{amount: "1000", currency: "KHR"}}
      }
    })
    |> json_response(201)

    origin = build_conn() |> signed_in(user!(:staff, pp))

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
            destination_station_id: sr.id,
            payment_method: "cash",
            parcels: [%{measurement_type: "kg", weight_kg: "1"}]
          }
        }
      })
      |> json_response(201)
      |> get_in(["data", "id"])

    %{
      admin: admin,
      origin: origin,
      id: id,
      pp: pp,
      sr: sr,
      destination: build_conn() |> signed_in(user!(:staff, sr)),
      dest_supervisor: build_conn() |> signed_in(user!(:supervisor, sr)),
      stranger: build_conn() |> signed_in(user!(:staff, station!("Other"))),
      other_supervisor: build_conn() |> signed_in(user!(:supervisor, station!("Other 2")))
    }
  end

  defp depart(conn, id) do
    patch(conn, "/api/v1/shipments/#{id}/in-transit", %{
      data: %{type: "shipment", id: id, attributes: %{}}
    })
    |> json_response(200)
  end

  defp report(conn, id, kind \\ "damaged") do
    post(conn, "/api/v1/incidents", %{
      data: %{type: "incident", attributes: %{shipment_id: id, kind: kind, note: "wet box"}}
    })
  end

  defp overdue(conn, query \\ "") do
    conn |> get("/api/v1/shipments/overdue#{query}") |> json_response(200) |> Map.fetch!("data")
  end

  defp arrive(conn, id) do
    patch(conn, "/api/v1/shipments/#{id}/arrived", %{
      data: %{type: "shipment", id: id, attributes: %{}}
    })
    |> json_response(200)
  end

  defp backdate_arrival(id, hours) do
    Ex.Repo.query!("ALTER TABLE status_events DISABLE TRIGGER status_events_append_only")

    Ex.Repo.query!(
      "UPDATE status_events SET inserted_at = now() AT TIME ZONE 'utc' - make_interval(hours => $2) WHERE shipment_id = $1 AND status = 'arrived'",
      [Ecto.UUID.dump!(id), hours]
    )
  end

  describe "incidents" do
    test "cannot be reported before departure", ctx do
      ctx.origin |> report(ctx.id) |> json_response(400)
      depart(ctx.origin, ctx.id)
      ctx.origin |> report(ctx.id, "lost") |> json_response(201)
    end

    test "either Station can report, others cannot", ctx do
      depart(ctx.origin, ctx.id)
      ctx.destination |> report(ctx.id) |> json_response(201)
      ctx.stranger |> report(ctx.id) |> json_response(403)
    end

    test "only an Admin resolves it, once, with a resolution", ctx do
      depart(ctx.origin, ctx.id)
      %{"data" => %{"id" => iid}} = ctx.origin |> report(ctx.id) |> json_response(201)

      resolve = fn conn, attrs ->
        patch(conn, "/api/v1/incidents/#{iid}/resolve", %{
          data: %{type: "incident", id: iid, attributes: attrs}
        })
      end

      resolve.(ctx.destination, %{resolution: "paid"}) |> json_response(403)
      resolve.(ctx.other_supervisor, %{resolution: "paid"}) |> json_response(403)
      resolve.(ctx.dest_supervisor, %{resolution: "paid"}) |> json_response(403)
      resolve.(ctx.admin, %{}) |> json_response(400)

      assert %{"data" => %{"attributes" => %{"status" => "resolved"}}} =
               resolve.(ctx.admin, %{resolution: "paid"}) |> json_response(200)

      resolve.(ctx.admin, %{resolution: "again"}) |> json_response(400)
    end
  end

  describe "overdue" do
    test "only Arrived Shipments count, from the day they arrived", ctx do
      assert overdue(ctx.destination) == []
      depart(ctx.origin, ctx.id)
      assert overdue(ctx.destination) == []

      arrive(ctx.destination, ctx.id)
      assert overdue(ctx.destination) == []

      backdate_arrival(ctx.id, 47)
      assert overdue(ctx.destination) == []

      backdate_arrival(ctx.id, 49)
      assert [%{"id" => id}] = overdue(ctx.destination)
      assert id == ctx.id
    end

    test "a Shipment still In Transit is never Overdue", ctx do
      depart(ctx.origin, ctx.id)
      Ex.Repo.query!("ALTER TABLE status_events DISABLE TRIGGER status_events_append_only")

      Ex.Repo.query!(
        "UPDATE status_events SET inserted_at = now() AT TIME ZONE 'utc' - interval '10 days' WHERE shipment_id = $1",
        [Ecto.UUID.dump!(ctx.id)]
      )

      Ex.Repo.query!("ALTER TABLE status_events ENABLE TRIGGER status_events_append_only")
      assert overdue(ctx.admin) == []
    end

    test "each destination Station's own threshold applies", ctx do
      depart(ctx.origin, ctx.id)
      arrive(ctx.destination, ctx.id)
      backdate_arrival(ctx.id, 30)
      assert overdue(ctx.destination) == []

      patch(ctx.admin, "/api/v1/stations/#{ctx.sr.id}/overdue-threshold", %{
        data: %{type: "station", id: ctx.sr.id, attributes: %{overdue_threshold_days: 1}}
      })
      |> json_response(200)

      assert [_] = overdue(ctx.destination)
    end

    test "staff see their own Station; an Admin sees all and can filter", ctx do
      depart(ctx.origin, ctx.id)
      arrive(ctx.destination, ctx.id)
      backdate_arrival(ctx.id, 49)

      assert [_] = overdue(ctx.destination)
      assert [_] = overdue(ctx.dest_supervisor)
      assert [] = overdue(ctx.stranger)
      assert [] = overdue(ctx.origin)

      assert [_] = overdue(ctx.admin)
      assert [_] = overdue(ctx.admin, "?destination_station_id=#{ctx.sr.id}")
      assert [] = overdue(ctx.admin, "?destination_station_id=#{ctx.pp.id}")
    end

    test "only an admin changes a threshold", ctx do
      patch(ctx.dest_supervisor, "/api/v1/stations/#{ctx.sr.id}/overdue-threshold", %{
        data: %{type: "station", id: ctx.sr.id, attributes: %{overdue_threshold_days: 1}}
      })
      |> json_response(403)
    end
  end
end
