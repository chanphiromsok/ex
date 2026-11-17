defmodule ExWeb.Api.CancellationTest do
  @moduledoc """
  A Received Shipment can be cancelled by its origin Station. By default a Supervisor of that Station
  approves; the fee is a percent of the total (with an optional cap) and the rest is refunded.
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

    %{
      admin: admin,
      pp: pp,
      sr: sr,
      staff: build_conn() |> signed_in(user!(:staff, pp)),
      supervisor: build_conn() |> signed_in(user!(:supervisor, pp)),
      other_supervisor: build_conn() |> signed_in(user!(:supervisor, pp)),
      far_supervisor: build_conn() |> signed_in(user!(:supervisor, sr))
    }
  end

  defp send_shipment(conn, sr, kg \\ "10") do
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
          destination_station_id: sr.id,
          payment_method: "cash",
          parcels: [%{measurement_type: "kg", weight_kg: kg}]
        }
      }
    })
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp request_cancel(conn, id, reason \\ "customer changed mind") do
    post(conn, "/api/v1/cancellation-requests", %{
      data: %{
        type: "cancellation-request",
        attributes: %{shipment_id: id, reason: reason}
      }
    })
  end

  defp decide(conn, request_id, step, attrs \\ %{}) do
    patch(conn, "/api/v1/cancellation-requests/#{request_id}/#{step}", %{
      data: %{type: "cancellation-request", id: request_id, attributes: attrs}
    })
  end

  defp set_fee(conn, percent, cap \\ nil) do
    attrs = %{percent: percent}
    attrs = if cap, do: Map.put(attrs, :cap, %{amount: cap, currency: "KHR"}), else: attrs

    post(conn, "/api/v1/pricing/cancellation-fee", %{
      data: %{type: "cancellation-fee-setting", attributes: attrs}
    })
  end

  defp shipment(conn, id) do
    conn
    |> get("/api/v1/shipments/#{id}?include=payments")
    |> json_response(200)
  end

  defp payments(body) do
    for(
      %{"type" => "payment", "attributes" => a} <- body["included"],
      do: {a["kind"], a["amount"]["amount"]}
    )
    |> Enum.sort_by(&elem(&1, 0))
  end

  describe "with approval (the default)" do
    test "staff asks, an origin Supervisor approves, the fee is kept and the rest refunded",
         ctx do
      set_fee(ctx.admin, 10) |> json_response(201)
      id = send_shipment(ctx.staff, ctx.sr)

      %{"data" => %{"id" => rid, "attributes" => %{"status" => "pending"}}} =
        ctx.staff |> request_cancel(id) |> json_response(201)

      assert status(ctx.staff, id) == "received"

      assert %{
               "data" => %{
                 "attributes" => %{
                   "status" => "approved",
                   "fee" => fee,
                   "refund_amount" => refund
                 }
               }
             } =
               ctx.supervisor |> decide(rid, "approve") |> json_response(200)

      assert fee["amount"] == "1000"
      assert refund["amount"] == "9000"
      assert status(ctx.staff, id) == "cancelled"

      assert payments(shipment(ctx.staff, id)) == [{"payment", "10000"}, {"refund", "-9000"}]
    end

    test "the person who asked cannot approve their own request", ctx do
      id = send_shipment(ctx.supervisor, ctx.sr)
      %{"data" => %{"id" => rid}} = ctx.supervisor |> request_cancel(id) |> json_response(201)

      ctx.supervisor |> decide(rid, "approve") |> json_response(400)
      assert status(ctx.staff, id) == "received"

      ctx.other_supervisor |> decide(rid, "approve") |> json_response(200)
      assert status(ctx.staff, id) == "cancelled"
    end

    test "a rejection needs a reason and leaves the Shipment Received", ctx do
      id = send_shipment(ctx.staff, ctx.sr)
      %{"data" => %{"id" => rid}} = ctx.staff |> request_cancel(id) |> json_response(201)

      ctx.supervisor |> decide(rid, "reject") |> json_response(400)

      assert %{"data" => %{"attributes" => %{"status" => "rejected", "decision_reason" => "no"}}} =
               ctx.supervisor
               |> decide(rid, "reject", %{decision_reason: "no"})
               |> json_response(200)

      assert status(ctx.staff, id) == "received"
      ctx.supervisor |> decide(rid, "approve") |> json_response(400)
    end

    test "only an origin Station Supervisor can decide, and staff cannot", ctx do
      id = send_shipment(ctx.staff, ctx.sr)
      %{"data" => %{"id" => rid}} = ctx.staff |> request_cancel(id) |> json_response(201)

      ctx.staff |> decide(rid, "approve") |> json_response(403)
      ctx.far_supervisor |> decide(rid, "approve") |> json_response(403)
      assert status(ctx.staff, id) == "received"
    end

    test "only one open request per Shipment, and only the origin Station can ask", ctx do
      id = send_shipment(ctx.staff, ctx.sr)
      ctx.staff |> request_cancel(id) |> json_response(201)
      ctx.staff |> request_cancel(id) |> json_response(400)

      id2 = send_shipment(ctx.staff, ctx.sr)

      build_conn()
      |> signed_in(user!(:staff, ctx.sr))
      |> request_cancel(id2)
      |> json_response(403)
    end
  end

  describe "approval after departure or by an Admin" do
    test "an Admin cannot approve, and approval is invalid once In Transit", ctx do
      id = send_shipment(ctx.staff, ctx.sr)
      %{"data" => %{"id" => rid}} = ctx.staff |> request_cancel(id) |> json_response(201)

      ctx.admin |> decide(rid, "approve") |> json_response(403)

      ctx.staff
      |> patch("/api/v1/shipments/#{id}/in-transit", %{
        data: %{type: "shipment", id: id, attributes: %{}}
      })
      |> json_response(200)

      ctx.supervisor |> decide(rid, "approve") |> json_response(400)
      assert status(ctx.staff, id) == "in_transit"
    end
  end

  describe "fee" do
    test "is capped, and a 100% fee refunds nothing", ctx do
      set_fee(ctx.admin, 50, "2000") |> json_response(201)
      id = send_shipment(ctx.staff, ctx.sr)
      %{"data" => %{"id" => rid}} = ctx.staff |> request_cancel(id) |> json_response(201)

      assert %{"data" => %{"attributes" => %{"fee" => %{"amount" => "2000"}}}} =
               ctx.supervisor |> decide(rid, "approve") |> json_response(200)

      assert payments(shipment(ctx.staff, id)) == [{"payment", "10000"}, {"refund", "-8000"}]

      set_fee(ctx.admin, 100) |> json_response(201)
      id2 = send_shipment(ctx.staff, ctx.sr, "5")
      %{"data" => %{"id" => rid2}} = ctx.staff |> request_cancel(id2) |> json_response(201)
      ctx.supervisor |> decide(rid2, "approve") |> json_response(200)
      assert payments(shipment(ctx.staff, id2)) == [{"payment", "5000"}]
    end

    test "rounds half up to whole riel", ctx do
      set_fee(ctx.admin, 15) |> json_response(201)
      id = send_shipment(ctx.staff, ctx.sr, "0.01")
      %{"data" => %{"id" => rid}} = ctx.staff |> request_cancel(id) |> json_response(201)

      assert %{"data" => %{"attributes" => %{"fee" => %{"amount" => "2"}}}} =
               ctx.supervisor |> decide(rid, "approve") |> json_response(200)
    end

    test "only an admin sets it, and every change is logged", ctx do
      ctx.supervisor |> set_fee(10) |> json_response(403)
      set_fee(ctx.admin, 120) |> json_response(400)
      set_fee(ctx.admin, 20) |> json_response(201)

      log = ctx.admin |> get("/api/v1/setting-changes") |> json_response(200)
      assert [%{"attributes" => %{"kind" => "cancellation_fee"}}] = log["data"]
      assert %{"data" => []} = ctx.staff |> get("/api/v1/setting-changes") |> json_response(200)
    end
  end

  describe "a Station that does not require approval" do
    test "cancels at once when staff ask", ctx do
      ctx.admin
      |> patch("/api/v1/stations/#{ctx.pp.id}/cancellation-approval", %{
        data: %{
          type: "station",
          id: ctx.pp.id,
          attributes: %{cancellation_requires_approval: false}
        }
      })
      |> json_response(200)

      id = send_shipment(ctx.staff, ctx.sr)

      assert %{"data" => %{"attributes" => %{"status" => "approved"}}} =
               ctx.staff |> request_cancel(id) |> json_response(201)

      assert status(ctx.staff, id) == "cancelled"
      assert payments(shipment(ctx.staff, id)) == [{"payment", "10000"}, {"refund", "-10000"}]
    end
  end

  describe "when it is too late" do
    test "an In Transit Shipment cannot be cancelled", ctx do
      id = send_shipment(ctx.staff, ctx.sr)

      ctx.staff
      |> patch("/api/v1/shipments/#{id}/in-transit", %{
        data: %{type: "shipment", id: id, attributes: %{}}
      })
      |> json_response(200)

      ctx.staff |> request_cancel(id) |> json_response(400)
    end
  end

  defp status(conn, id) do
    conn
    |> get("/api/v1/shipments/#{id}")
    |> json_response(200)
    |> get_in(["data", "attributes", "status"])
  end
end
