defmodule ExWeb.OpenApi do
  @moduledoc """
  Adds the page intro, tag descriptions and public-endpoint markers to the generated OpenAPI spec
  that Scalar renders at `/api/docs`.
  """

  @public_paths ["/users/sign-in", "/users/refresh"]

  @tag_descriptions %{
    "user" => "Accounts, roles, sessions and tokens.",
    "location" => "Cities and provinces a Station is in.",
    "station" => "Offices where staff receive and hand over Shipments.",
    "permission" => "The permissions a role can be given."
  }

  # Worked request bodies, keyed by {HTTP method, path suffix}. Money is whole riel (KHR).
  @examples %{
    {:post, "/users/sign-in"} => %{
      "data" => %{
        "type" => "user",
        "attributes" => %{"email" => "staff@example.com", "password" => "password123"}
      }
    },
    {:post, "/shipments"} => %{
      "data" => %{
        "type" => "shipment",
        "attributes" => %{
          "idempotency_key" => "6f1c1d0e-8a5b-4f43-9c1e-2b7d9a3f5e10",
          "sender_phone" => "012 345 678",
          "receiver_phone" => "097 111 2222",
          "destination_station_id" => "00000000-0000-0000-0000-000000000000",
          "payment_method" => "cash",
          "declared_value" => %{"amount" => "50000", "currency" => "KHR"},
          "parcels" => [
            %{"measurement_type" => "kg", "weight_kg" => "1.01"},
            %{
              "measurement_type" => "size",
              "size_class_id" => "00000000-0000-0000-0000-000000000000"
            }
          ],
          "sale_items" => [
            %{"sale_item_id" => "00000000-0000-0000-0000-000000000000", "quantity" => 2}
          ]
        }
      }
    },
    {:post, "/pricing/price-per-kg"} => %{
      "data" => %{
        "type" => "pricing-setting",
        "attributes" => %{"price_per_kg" => %{"amount" => "1250", "currency" => "KHR"}}
      }
    },
    {:post, "/pricing/cancellation-fee"} => %{
      "data" => %{
        "type" => "cancellation-fee-setting",
        "attributes" => %{"percent" => 10, "cap" => %{"amount" => "2000", "currency" => "KHR"}}
      }
    },
    {:post, "/cancellation-requests"} => %{
      "data" => %{
        "type" => "cancellation-request",
        "attributes" => %{
          "shipment_id" => "00000000-0000-0000-0000-000000000000",
          "reason" => "Customer changed their mind"
        }
      }
    },
    {:post, "/receiver-corrections"} => %{
      "data" => %{
        "type" => "receiver-correction",
        "attributes" => %{
          "shipment_id" => "00000000-0000-0000-0000-000000000000",
          "name" => "Chea Sophea",
          "phone" => "098 765 432",
          "reason" => "Receiver gave a different number"
        }
      }
    },
    {:post, "/shipment-notes"} => %{
      "data" => %{
        "type" => "shipment-note",
        "attributes" => %{
          "shipment_id" => "00000000-0000-0000-0000-000000000000",
          "body" => "Box damaged on arrival"
        }
      }
    },
    {:post, "/incidents"} => %{
      "data" => %{
        "type" => "incident",
        "attributes" => %{
          "shipment_id" => "00000000-0000-0000-0000-000000000000",
          "kind" => "damaged",
          "note" => "Corner crushed"
        }
      }
    }
  }

  def modify(spec, _conn, _opts) do
    %{
      spec
      | info: %{spec.info | description: intro()},
        tags: tags(spec),
        paths: Map.new(spec.paths, &(&1 |> mark_public() |> add_examples()))
    }
  end

  defp add_examples({path, item}) do
    item =
      Enum.reduce(@examples, item, fn {{method, suffix}, example}, item ->
        with true <- String.ends_with?(path, suffix),
             %{requestBody: %{content: %{"application/vnd.api+json" => media} = content} = body} =
               op <-
               Map.get(item, method) do
          media = %{media | example: example}

          Map.put(item, method, %{
            op
            | requestBody: %{body | content: %{content | "application/vnd.api+json" => media}}
          })
        else
          _ -> item
        end
      end)

    {path, item}
  end

  defp intro do
    """
    Express goods by bus, from a Station to a Station.

    **Walk-in story:** a staff member signs in, `POST /shipments` (Sender, Receiver, destination Station,
    Parcels, payment method) and gets the invoice back with `?include=parcels,sale_items,payments,status_events`;
    the origin Station marks it `in-transit`, the destination marks it `arrived`, then `collect` with the
    Receiver's phone. Prices, the Invoice Number and the origin Station are always set by the server.
    Money is whole riel (KHR); phones are stored as `855…`.

    **Getting started:** `POST /users/sign-in` with an email and password, then send the returned
    token as `Authorization: Bearer <token>`. Access tokens last one hour; renew them with
    `POST /users/refresh`.
    """
  end

  # AshJsonApi leaves `spec.tags` empty, so build one per tag used by an operation.
  defp tags(spec) do
    spec.paths
    |> Enum.flat_map(fn {_path, item} -> operations(item) end)
    |> Enum.flat_map(&(&1.tags || []))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&%OpenApiSpex.Tag{name: &1, description: Map.get(@tag_descriptions, &1)})
  end

  defp operations(item) do
    [:get, :post, :patch, :put, :delete] |> Enum.map(&Map.get(item, &1)) |> Enum.reject(&is_nil/1)
  end

  # Sign-in and refresh need no bearer token, so drop the spec-wide requirement for them.
  defp mark_public({path, item}) do
    if Enum.any?(@public_paths, &String.ends_with?(path, &1)) do
      {path, %{item | post: %{item.post | security: []}}}
    else
      {path, item}
    end
  end
end
