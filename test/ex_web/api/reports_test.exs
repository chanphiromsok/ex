defmodule ExWeb.Api.ReportsTest do
  @moduledoc """
  Cash and cancellation reports: a Supervisor sees only their Station, an Admin the whole company.
  """
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  @wide "from=2000-01-01T00:00:00Z&to=2100-01-01T00:00:00Z"

  setup %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    pp = station!("PP Central")
    sr = station!("SR Central")

    for {a, b} <- [{pp, sr}, {sr, pp}] do
      Ash.create!(
        Ex.Network.Route,
        %{origin_location_id: a.location_id, destination_location_id: b.location_id},
        authorize?: false
      )
    end

    post(admin, "/api/v1/pricing/price-per-kg", %{
      data: %{
        type: "pricing-setting",
        attributes: %{price_per_kg: %{amount: "1000", currency: "KHR"}}
      }
    })
    |> json_response(201)

    pp_staff_user = user!(:staff, pp)

    %{
      admin: admin,
      pp: pp,
      sr: sr,
      pp_staff: build_conn() |> signed_in(pp_staff_user),
      pp_staff_email: to_string(pp_staff_user.email),
      sr_staff: build_conn() |> signed_in(user!(:staff, sr)),
      pp_supervisor: build_conn() |> signed_in(user!(:supervisor, pp)),
      other_pp_supervisor: build_conn() |> signed_in(user!(:supervisor, pp))
    }
  end

  defp send_shipment(conn, to, kg, method \\ "cash") do
    conn
    |> post("/api/v1/shipments", %{
      data: %{
        type: "shipment",
        attributes: %{
          idempotency_key: Ecto.UUID.generate(),
          sender_name: "Sok Dara",
          sender_phone: "012 345 678",
          receiver_name: "Chea Srey",
          receiver_phone: "097 111 2222",
          destination_station_id: to.id,
          payment_method: method,
          parcels: [%{measurement_type: "kg", weight_kg: kg}]
        }
      }
    })
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp cancel(requester, approver, id) do
    %{"data" => %{"id" => rid}} =
      requester
      |> post("/api/v1/cancellation-requests", %{
        data: %{
          type: "cancellation-request",
          attributes: %{shipment_id: id, reason: "changed mind"}
        }
      })
      |> json_response(201)

    patch(approver, "/api/v1/cancellation-requests/#{rid}/approve", %{
      data: %{type: "cancellation-request", id: rid, attributes: %{}}
    })
    |> json_response(200)
  end

  defp report(conn, path, query \\ @wide) do
    conn |> get("/api/v1/reports/#{path}?#{query}") |> json_response(200)
  end

  describe "cash" do
    test "refunds reduce the total", ctx do
      send_shipment(ctx.pp_staff, ctx.sr, "10")
      id = send_shipment(ctx.pp_staff, ctx.sr, "5")
      cancel(ctx.pp_staff, ctx.pp_supervisor, id)

      # A refund counts against whoever recorded it (the approving Supervisor), as the ledger says.
      rows = report(ctx.pp_supervisor, "cash")
      assert [taken] = Enum.filter(rows, &(&1["email"] == ctx.pp_staff_email))
      assert taken["cash_taken"] == "15000"
      assert taken["net_cash"] == "15000"
      assert [refunded] = Enum.reject(rows, &(&1["email"] == ctx.pp_staff_email))
      assert refunded["cash_refunded"] == "5000"
      assert refunded["net_cash"] == "-5000"
      assert Enum.sum(for r <- rows, do: String.to_integer(r["net_cash"])) == 10_000
    end

    test "non-cash payments are left out", ctx do
      send_shipment(ctx.pp_staff, ctx.sr, "10", "qr")
      assert report(ctx.pp_supervisor, "cash") == []
    end

    test "the window is any start and end, including across midnight", ctx do
      send_shipment(ctx.pp_staff, ctx.sr, "10")
      now = DateTime.utc_now()
      iso = &(&1 |> DateTime.truncate(:second) |> DateTime.to_iso8601())

      inside = "from=#{iso.(DateTime.add(now, -60))}&to=#{iso.(DateTime.add(now, 60))}"
      assert [_] = report(ctx.pp_supervisor, "cash", inside)

      before = "from=#{iso.(DateTime.add(now, -7200))}&to=#{iso.(DateTime.add(now, -3600))}"
      assert [] = report(ctx.pp_supervisor, "cash", before)

      # A window that starts the previous evening and ends after midnight is just two instants.
      overnight = "from=#{iso.(DateTime.add(now, -86_400))}&to=#{iso.(DateTime.add(now, 86_400))}"
      assert [_] = report(ctx.pp_supervisor, "cash", overnight)
    end

    test "a Supervisor sees only their Station; an Admin sees everyone", ctx do
      send_shipment(ctx.pp_staff, ctx.sr, "10")
      send_shipment(ctx.sr_staff, ctx.pp, "3")

      assert [%{"net_cash" => "10000"}] = report(ctx.pp_supervisor, "cash")
      assert [_, _] = report(ctx.admin, "cash")
    end

    test "staff cannot read it and from/to are required", ctx do
      ctx.pp_staff |> get("/api/v1/reports/cash?#{@wide}") |> json_response(403)
      ctx.pp_supervisor |> get("/api/v1/reports/cash") |> json_response(400)
    end
  end

  describe "cancellations" do
    test "counts per staff member and keeps Stations apart", ctx do
      id = send_shipment(ctx.pp_staff, ctx.sr, "10")
      cancel(ctx.pp_staff, ctx.pp_supervisor, id)
      other = send_shipment(ctx.sr_staff, ctx.pp, "2")
      cancel(ctx.sr_staff, build_conn() |> signed_in(user!(:supervisor, ctx.sr)), other)

      assert [row] = report(ctx.other_pp_supervisor, "cancellations")
      assert row["email"] == ctx.pp_staff_email
      assert row["approved"] == 1
      assert row["refunded"] == "10000"

      assert [_, _] = report(ctx.admin, "cancellations")
    end
  end
end
