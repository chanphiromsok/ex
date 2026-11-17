defmodule ExWeb.Api.ShipmentsTest do
  @moduledoc """
  User story: a walk-in Sender comes to our Phnom Penh Station and sends goods to Siem Reap.
  Every expected number below was worked out by hand first.
  """
  use ExWeb.ConnCase, async: true
  import Ex.Fixtures

  defp khr(amount), do: %{amount: to_string(amount), currency: "KHR"}

  # PP Central -> Siem Reap Central, price per kg 1250, a Box at 5000, a Tape at 1500.
  setup %{conn: conn} do
    admin = conn |> signed_in(user!(:admin))
    pp_station = station!("PP Central")
    sr_station = station!("SR Central")

    {:ok, route} =
      Ash.create(
        Ex.Network.Route,
        %{
          origin_location_id: pp_station.location_id,
          destination_location_id: sr_station.location_id
        },
        authorize?: false
      )

    post(admin, "/api/v1/pricing/price-per-kg", %{
      data: %{type: "pricing-setting", attributes: %{price_per_kg: khr(1250)}}
    })
    |> json_response(201)

    box = create_size_class(admin, "Box", 5000)
    tape = create_sale_item(admin, "Tape", 1500)

    %{
      admin: admin,
      pp_station: pp_station,
      sr_station: sr_station,
      route: route,
      box: box,
      tape: tape,
      clerk: build_conn() |> signed_in(user!(:staff, pp_station))
    }
  end

  defp create_size_class(admin, name, price) do
    admin
    |> post("/api/v1/size-classes", %{
      data: %{
        type: "size-class",
        attributes: %{name_en: name, name_km: "km " <> name, price: khr(price)}
      }
    })
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp create_sale_item(admin, name, price) do
    admin
    |> post("/api/v1/sale-items", %{
      data: %{
        type: "sale-item",
        attributes: %{name_en: name, name_km: "km " <> name, unit_price: khr(price)}
      }
    })
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp attributes(ctx, overrides \\ %{}) do
    Map.merge(
      %{
        idempotency_key: Ecto.UUID.generate(),
        sender_name: "Sok Dara",
        sender_phone: "012 345 678",
        receiver_name: "Chea Srey",
        receiver_phone: "+855 97 111 2222",
        destination_station_id: ctx.sr_station.id,
        payment_method: "cash",
        parcels: [
          %{measurement_type: "kg", weight_kg: "1.01"},
          %{measurement_type: "size", size_class_id: ctx.box}
        ],
        sale_items: [%{sale_item_id: ctx.tape, quantity: 2}]
      },
      overrides
    )
  end

  defp send_shipment(conn, attrs) do
    post(conn, "/api/v1/shipments?include=parcels,sale_items,payments,status_events", %{
      data: %{type: "shipment", attributes: attrs}
    })
  end

  defp included(body, type), do: Enum.filter(body["included"] || [], &(&1["type"] == type))

  describe "the walk-in story" do
    test "1.01 kg + one Box + two Tapes, paid in cash", ctx do
      body = ctx.clerk |> send_shipment(attributes(ctx)) |> json_response(201)
      shipment = body["data"]["attributes"]

      # 1.01 kg * 1250 = 1262.5 -> 1263 (half up; banker's rounding would give 1262)
      # + Box 5000 + 2 * Tape 1500 = 3000  =>  1263 + 5000 + 3000 = 9263
      assert shipment["shipment_total"] == %{"amount" => "9263", "currency" => "KHR"}
      assert is_integer(shipment["invoice_no"])
      assert shipment["sender_phone"] == "85512345678"
      assert shipment["receiver_phone"] == "855971112222"
      assert shipment["origin_station_id"] == ctx.pp_station.id
      assert shipment["route_id"] == ctx.route.id

      amounts =
        body
        |> included("parcel")
        |> Enum.map(&get_in(&1, ["attributes", "chargeable_amount", "amount"]))
        |> Enum.sort()

      assert amounts == ["1263", "5000"]

      assert [item] = included(body, "shipment-sale-item")
      assert item["attributes"]["quantity"] == 2
      assert item["attributes"]["unit_price"]["amount"] == "1500"

      # the Payment is the whole total, and the clerk did not choose the amount
      assert [payment] = included(body, "payment")
      assert payment["attributes"]["amount"] == %{"amount" => "9263", "currency" => "KHR"}
      assert payment["attributes"]["method"] == "cash"
      assert payment["attributes"]["kind"] == "payment"

      # exactly one status event: received
      assert [event] = included(body, "status-event")
      assert event["attributes"]["status"] == "received"
      assert event["attributes"]["seq"] == 1
      assert event["attributes"]["status_label_en"] == "Received"

      # the stored total is the sum of the stored lines
      lines =
        Enum.map(included(body, "parcel"), &amount(&1["attributes"]["chargeable_amount"])) ++
          [amount(item["attributes"]["unit_price"]) * item["attributes"]["quantity"]]

      assert Enum.sum(lines) == amount(shipment["shipment_total"])
    end

    test "names are optional: only the two phones are needed", ctx do
      attrs = ctx |> attributes() |> Map.drop([:sender_name, :receiver_name])
      body = ctx.clerk |> send_shipment(attrs) |> json_response(201)

      assert body["data"]["attributes"]["sender_name"] == nil
      assert body["data"]["attributes"]["receiver_phone"] == "855971112222"
    end

    test "the invoice can be read again by anyone with shipment.read", ctx do
      id =
        ctx.clerk
        |> send_shipment(attributes(ctx))
        |> json_response(201)
        |> get_in(["data", "id"])

      shown = ctx.clerk |> get("/api/v1/shipments/#{id}") |> json_response(200)
      assert shown["data"]["attributes"]["status"] == "received"
      assert shown["data"]["attributes"]["status_label_km"] == "បានទទួល"
    end

    test "repeating the same idempotency key returns the same Shipment", ctx do
      attrs = attributes(ctx)

      first = ctx.clerk |> send_shipment(attrs) |> json_response(201)
      second = ctx.clerk |> send_shipment(attrs) |> json_response(201)

      assert first["data"]["id"] == second["data"]["id"]

      assert first["data"]["attributes"]["invoice_no"] ==
               second["data"]["attributes"]["invoice_no"]

      # nothing was added the second time
      assert [_, _] = included(second, "parcel")
      assert [_] = included(second, "payment")
      assert [_] = included(second, "status-event")
    end

    test "another user cannot take over someone else's idempotency key", ctx do
      attrs = attributes(ctx)
      ctx.clerk |> send_shipment(attrs) |> json_response(201)

      other = build_conn() |> signed_in(user!(:staff, ctx.pp_station))
      assert other |> send_shipment(attrs) |> json_response(400)
    end

    test "a later price change never alters an existing total", ctx do
      id =
        ctx.clerk
        |> send_shipment(attributes(ctx))
        |> json_response(201)
        |> get_in(["data", "id"])

      post(ctx.admin, "/api/v1/pricing/price-per-kg", %{
        data: %{type: "pricing-setting", attributes: %{price_per_kg: khr(9999)}}
      })
      |> json_response(201)

      patch(ctx.admin, "/api/v1/size-classes/#{ctx.box}/price", %{
        data: %{type: "size-class", id: ctx.box, attributes: %{price: khr(9999)}}
      })
      |> json_response(200)

      shown = ctx.clerk |> get("/api/v1/shipments/#{id}") |> json_response(200)
      assert shown["data"]["attributes"]["shipment_total"]["amount"] == "9263"
    end
  end

  describe "the server decides the money" do
    test "a price sent by the clerk is not accepted or used", ctx do
      attrs =
        attributes(ctx, %{
          shipment_total: khr(1),
          parcels: [%{measurement_type: "kg", weight_kg: "1.01", chargeable_amount: khr(1)}]
        })

      response = ctx.clerk |> send_shipment(attrs)

      case response.status do
        201 ->
          body = json_response(response, 201)
          assert body["data"]["attributes"]["shipment_total"]["amount"] != "1"

        status ->
          assert status in [400, 422]
      end
    end

    test "weight with more than two decimals is rejected", ctx do
      attrs = attributes(ctx, %{parcels: [%{measurement_type: "kg", weight_kg: "2.555"}]})
      assert ctx.clerk |> send_shipment(attrs) |> json_response(400)
    end

    test "a kg Parcel without a weight is rejected", ctx do
      attrs = attributes(ctx, %{parcels: [%{measurement_type: "kg"}]})
      assert ctx.clerk |> send_shipment(attrs) |> json_response(400)
    end

    test "a size Parcel without a Size Class is rejected", ctx do
      attrs = attributes(ctx, %{parcels: [%{measurement_type: "size"}]})
      assert ctx.clerk |> send_shipment(attrs) |> json_response(400)
    end

    test "a Shipment with no Parcels is rejected", ctx do
      assert ctx.clerk |> send_shipment(attributes(ctx, %{parcels: []})) |> json_response(400)
    end

    test "an inactive Size Class is rejected", ctx do
      patch(ctx.admin, "/api/v1/size-classes/#{ctx.box}", %{
        data: %{type: "size-class", id: ctx.box, attributes: %{active: false}}
      })
      |> json_response(200)

      assert ctx.clerk |> send_shipment(attributes(ctx)) |> json_response(400)
    end

    test "a quantity of zero is rejected", ctx do
      attrs = attributes(ctx, %{sale_items: [%{sale_item_id: ctx.tape, quantity: 0}]})
      assert ctx.clerk |> send_shipment(attrs) |> json_response(400)
    end

    test "a declared value must be a whole number of riel", ctx do
      attrs = attributes(ctx, %{declared_value: khr("10.5")})
      assert ctx.clerk |> send_shipment(attrs) |> json_response(400)
    end
  end

  describe "stations and routes" do
    test "the origin is the clerk's own Station", ctx do
      body = ctx.clerk |> send_shipment(attributes(ctx)) |> json_response(201)
      assert body["data"]["attributes"]["origin_station_id"] == ctx.pp_station.id
    end

    test "there is no Route back from Siem Reap to Phnom Penh", ctx do
      sr_clerk = build_conn() |> signed_in(user!(:staff, ctx.sr_station))
      attrs = attributes(ctx, %{destination_station_id: ctx.pp_station.id})
      assert sr_clerk |> send_shipment(attrs) |> json_response(400)
    end

    test "a Station cannot send to itself", ctx do
      attrs = attributes(ctx, %{destination_station_id: ctx.pp_station.id})
      assert ctx.clerk |> send_shipment(attrs) |> json_response(400)
    end

    test "an admin has no Station, so cannot create a Shipment", ctx do
      assert ctx.admin |> send_shipment(attributes(ctx)) |> response(:forbidden)
    end
  end

  describe "phone numbers" do
    for {label, phone} <- [
          {"too short", "012"},
          {"letters", "abcdefghi"},
          {"starts with 0 after the code", "855012345678"}
        ] do
      test "a #{label} phone is rejected", ctx do
        attrs = attributes(ctx, %{sender_phone: unquote(phone)})
        assert ctx.clerk |> send_shipment(attrs) |> json_response(400)
      end
    end
  end

  describe "the Invoice Number under load" do
    test "parallel Shipments each get a different number", ctx do
      results =
        1..15
        |> Task.async_stream(
          fn _ ->
            build_conn()
            |> Plug.Conn.put_req_header("authorization", ctx.clerk |> bearer())
            |> Plug.Conn.put_req_header("accept", "application/vnd.api+json")
            |> Plug.Conn.put_req_header("content-type", "application/vnd.api+json")
            |> send_shipment(attributes(ctx))
            |> json_response(201)
            |> get_in(["data", "attributes", "invoice_no"])
          end,
          max_concurrency: 15,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, number} -> number end)

      assert length(Enum.uniq(results)) == 15
    end
  end

  describe "the database keeps history untouchable" do
    test "a Payment and a status event cannot be changed or deleted", ctx do
      ctx.clerk |> send_shipment(attributes(ctx)) |> json_response(201)

      for table <- ["payments", "status_events"] do
        assert_raise Postgrex.Error, ~r/cannot be changed or deleted/, fn ->
          Ex.Repo.query!("DELETE FROM #{table}")
        end
      end
    end
  end

  defp amount(%{"amount" => amount}), do: amount |> Decimal.new() |> Decimal.to_integer()

  defp bearer(conn), do: conn |> Plug.Conn.get_req_header("authorization") |> hd()
end
