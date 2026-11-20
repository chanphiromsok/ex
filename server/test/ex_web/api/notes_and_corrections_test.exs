defmodule ExWeb.Api.NotesAndCorrectionsTest do
  @moduledoc """
  Ticket #6: the destination adds Notes, the origin Supervisor adds Receiver Corrections,
  and the latest correction is the Receiver for search and Collection.
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

    origin = build_conn() |> signed_in(user!(:staff, pp))
    origin_supervisor = build_conn() |> signed_in(user!(:supervisor, pp))
    destination = build_conn() |> signed_in(user!(:staff, sr))
    destination_supervisor = build_conn() |> signed_in(user!(:supervisor, sr))

    body =
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

    %{
      origin: origin,
      origin_supervisor: origin_supervisor,
      destination: destination,
      destination_supervisor: destination_supervisor,
      id: body["data"]["id"],
      invoice_no: body["data"]["attributes"]["invoice_no"]
    }
  end

  defp move(conn, id, step, attrs \\ %{}),
    do:
      patch(conn, "/api/v1/shipments/#{id}/#{step}", %{
        data: %{type: "shipment", id: id, attributes: attrs}
      })

  defp note(conn, id, text),
    do:
      post(conn, "/api/v1/shipment-notes", %{
        data: %{type: "shipment-note", attributes: %{shipment_id: id, body: text}}
      })

  defp correct(conn, id, attrs),
    do:
      post(conn, "/api/v1/receiver-corrections", %{
        data: %{type: "receiver-correction", attributes: Map.put(attrs, :shipment_id, id)}
      })

  defp depart(ctx), do: ctx.origin |> move(ctx.id, "in-transit") |> json_response(200)

  defp arrive(ctx) do
    depart(ctx)
    ctx.destination |> move(ctx.id, "arrived") |> json_response(200)
  end

  defp search(conn, query),
    do: conn |> get("/api/v1/shipments?#{query}") |> json_response(200) |> Map.fetch!("data")

  describe "Notes" do
    test "the destination can add a Note once the Shipment is in transit or arrived", ctx do
      depart(ctx)
      assert ctx.destination |> note(ctx.id, "Box is wet") |> json_response(201)

      shipment =
        ctx.destination |> get("/api/v1/shipments/#{ctx.id}?include=notes") |> json_response(200)

      assert [%{"attributes" => %{"body" => "Box is wet"}}] = shipment["included"]
    end

    test "origin and other Stations cannot add a Note", ctx do
      depart(ctx)
      assert ctx.origin |> note(ctx.id, "x") |> json_response(403)
    end

    test "a Note cannot be added before departure or after Collection", ctx do
      assert ctx.destination |> note(ctx.id, "too early") |> json_response(400)

      arrive(ctx)

      ctx.destination
      |> move(ctx.id, "collect", %{receiver_phone: "0971112222"})
      |> json_response(200)

      assert ctx.destination |> note(ctx.id, "too late") |> json_response(400)
    end

    test "Notes cannot be edited or deleted", ctx do
      depart(ctx)

      %{"data" => %{"id" => note_id}} =
        ctx.destination |> note(ctx.id, "ok") |> json_response(201)

      assert ctx.destination
             |> patch("/api/v1/shipment-notes/#{note_id}", %{
               data: %{type: "shipment-note", id: note_id, attributes: %{body: "x"}}
             })
             |> response(404)

      assert ctx.destination |> delete("/api/v1/shipment-notes/#{note_id}") |> response(404)
    end

    test "the destination cannot change weight, price or phones", ctx do
      arrive(ctx)

      for attrs <- [
            %{receiver_phone: "0971119999"},
            %{sender_phone: "0123"},
            %{shipment_total: %{amount: "1", currency: "KHR"}}
          ] do
        conn = move(ctx.destination, ctx.id, "arrived", attrs)
        assert conn.status in [400, 403, 404]
      end

      shipment = ctx.destination |> get("/api/v1/shipments/#{ctx.id}") |> json_response(200)
      assert shipment["data"]["attributes"]["receiver_phone"] == "855971112222"
    end
  end

  describe "Receiver Corrections" do
    test "only a Supervisor at the origin Station can add one", ctx do
      depart(ctx)
      attrs = %{name: "Lim Sokha", phone: "098 765 432", reason: "Wrong name given"}

      assert ctx.origin |> correct(ctx.id, attrs) |> json_response(403)
      assert ctx.destination_supervisor |> correct(ctx.id, attrs) |> json_response(403)

      body = ctx.origin_supervisor |> correct(ctx.id, attrs) |> json_response(201)
      assert body["data"]["attributes"]["phone"] == "85598765432"
    end

    test "not possible before departure or after Collection", ctx do
      attrs = %{name: "Lim Sokha", phone: "098 765 432", reason: "Typo"}
      assert ctx.origin_supervisor |> correct(ctx.id, attrs) |> json_response(400)

      arrive(ctx)

      ctx.destination
      |> move(ctx.id, "collect", %{receiver_phone: "0971112222"})
      |> json_response(200)

      assert ctx.origin_supervisor |> correct(ctx.id, attrs) |> json_response(400)
    end

    test "needs a reason and a valid phone", ctx do
      depart(ctx)

      assert ctx.origin_supervisor
             |> correct(ctx.id, %{name: "A", phone: "098 765 432"})
             |> json_response(400)

      assert ctx.origin_supervisor
             |> correct(ctx.id, %{name: "A", phone: "abc", reason: "x"})
             |> json_response(400)
    end

    test "are appended, never edited, and the latest one is the Receiver", ctx do
      depart(ctx)

      first =
        ctx.origin_supervisor
        |> correct(ctx.id, %{name: "First", phone: "098 765 432", reason: "one"})
        |> json_response(201)

      ctx.origin_supervisor
      |> correct(ctx.id, %{name: "Second", phone: "096 555 4444", reason: "two"})
      |> json_response(201)

      id = first["data"]["id"]

      assert ctx.origin_supervisor
             |> patch("/api/v1/receiver-corrections/#{id}", %{
               data: %{type: "receiver-correction", id: id, attributes: %{name: "x"}}
             })
             |> response(404)

      body =
        ctx.origin
        |> get("/api/v1/shipments/#{ctx.id}?include=receiver_corrections")
        |> json_response(200)

      assert length(body["included"]) == 2
      assert body["data"]["attributes"]["current_receiver_name"] == "Second"
      assert body["data"]["attributes"]["current_receiver_phone"] == "855965554444"
      assert body["data"]["attributes"]["receiver_phone"] == "855971112222"
    end
  end

  describe "search at the destination" do
    test "finds a Shipment by Invoice Number from any Station", ctx do
      assert [%{"id" => id}] = search(ctx.destination, "filter[invoice_no]=#{ctx.invoice_no}")
      assert id == ctx.id
    end

    test "finds by Receiver phone, and uses the latest correction even after arrival", ctx do
      arrive(ctx)
      assert [_] = search(ctx.destination, "filter[current_receiver_phone]=855971112222")

      ctx.origin_supervisor
      |> correct(ctx.id, %{name: "New", phone: "098 765 432", reason: "changed"})
      |> json_response(201)

      assert [] = search(ctx.destination, "filter[current_receiver_phone]=855971112222")

      assert [%{"id" => id}] =
               search(ctx.destination, "filter[current_receiver_phone]=85598765432")

      assert id == ctx.id
    end
  end

  describe "Collection uses the latest Receiver" do
    test "the corrected phone collects, the original no longer does", ctx do
      depart(ctx)

      ctx.origin_supervisor
      |> correct(ctx.id, %{name: "Lim", phone: "098 765 432", reason: "changed"})
      |> json_response(201)

      ctx.destination |> move(ctx.id, "arrived") |> json_response(200)

      assert [_] = search(ctx.destination, "filter[current_receiver_phone]=85598765432")
      assert [] = search(ctx.destination, "filter[current_receiver_phone]=855971112222")

      assert ctx.destination
             |> move(ctx.id, "collect", %{receiver_phone: "097 111 2222"})
             |> json_response(400)

      assert ctx.destination
             |> move(ctx.id, "collect", %{receiver_phone: "098 765 432"})
             |> json_response(200)
    end
  end
end
