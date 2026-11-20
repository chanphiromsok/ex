defmodule Ex.Shipping.Changes.PlaceShipment do
  @moduledoc """
  Everything a Shipment needs that the client must not decide: its origin Station (the actor's own),
  its Route, its prices and the Shipment Total.

  The prices are worked out once, before the insert, kept in the changeset context, and the children
  (Parcels, Sale Item lines, first Status Event, first Payment) are written from those same numbers
  in the same transaction. A repeated request (same idempotency key) finds the first Shipment's rows
  and writes nothing more.
  """
  use Ash.Resource.Change

  alias Ex.Shipping.Pricing

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    changeset
    |> Ash.Changeset.before_action(&price_and_route(&1, actor))
    |> Ash.Changeset.after_action(&write_children(&1, &2, actor))
  end

  defp price_and_route(changeset, actor) do
    destination_id = Ash.Changeset.get_attribute(changeset, :destination_station_id)

    with {:ok, origin} <- station(actor.station_id, :origin_station_id),
         {:ok, destination} <- station(destination_id, :destination_station_id),
         :ok <- different(origin, destination),
         {:ok, route} <- route(origin, destination),
         {:ok, priced} <-
           Pricing.price(
             Ash.Changeset.get_argument(changeset, :parcels) || [],
             Ash.Changeset.get_argument(changeset, :sale_items) || []
           ) do
      changeset
      |> Ash.Changeset.force_change_attribute(:origin_station_id, origin.id)
      |> Ash.Changeset.force_change_attribute(:route_id, route.id)
      |> Ash.Changeset.force_change_attribute(:created_by_id, actor.id)
      |> Ash.Changeset.force_change_attribute(:shipment_total, priced.total)
      |> Ash.Changeset.set_context(%{priced: priced})
    else
      {:error, {field, message}} ->
        Ash.Changeset.add_error(changeset, field: field, message: message)
    end
  end

  defp station(nil, field), do: {:error, {field, "is required"}}

  defp station(id, field) do
    case Ash.get(Ex.Network.Station, id, authorize?: false) do
      {:ok, %{active: true} = station} -> {:ok, station}
      {:ok, _} -> {:error, {field, "is not an active Station"}}
      _ -> {:error, {field, "does not exist"}}
    end
  end

  defp different(%{id: id}, %{id: id}),
    do: {:error, {:destination_station_id, "must differ from your own Station"}}

  defp different(_, _), do: :ok

  defp route(origin, destination) do
    case Ex.Network.Route
         |> Ash.Query.filter(
           origin_location_id == ^origin.location_id and
             destination_location_id == ^destination.location_id
         )
         |> Ash.read_one(authorize?: false) do
      {:ok, %{} = route} -> {:ok, route}
      _ -> {:error, {:destination_station_id, "there is no Route to that Location"}}
    end
  end

  defp write_children(changeset, shipment, actor) do
    priced = changeset.context[:priced]

    cond do
      shipment.created_by_id != actor.id ->
        {:error,
         Ash.Error.Changes.InvalidAttribute.exception(
           field: :idempotency_key,
           message: "was already used by someone else"
         )}

      Ash.exists?(Ex.Shipping.Parcel |> Ash.Query.filter(shipment_id == ^shipment.id),
        authorize?: false
      ) ->
        {:ok, shipment}

      true ->
        create_all(changeset, shipment, actor, priced)
    end
  end

  defp create_all(changeset, shipment, actor, priced) do
    opts = [authorize?: false]

    Enum.each(priced.parcels, fn line ->
      Ash.create!(Ex.Shipping.Parcel, Map.put(line, :shipment_id, shipment.id), opts)
    end)

    Enum.each(priced.sale_items, fn line ->
      Ash.create!(
        Ex.Shipping.ShipmentSaleItem,
        %{
          shipment_id: shipment.id,
          sale_item_id: line.sale_item_id,
          quantity: line.quantity,
          unit_price: line.unit_price
        },
        opts
      )
    end)

    Ash.create!(
      Ex.Shipping.StatusEvent,
      %{
        shipment_id: shipment.id,
        seq: 1,
        status: :received,
        station_id: actor.station_id,
        created_by_id: actor.id
      },
      opts
    )

    Ash.create!(
      Ex.Shipping.Payment,
      %{
        shipment_id: shipment.id,
        method: Ash.Changeset.get_argument(changeset, :payment_method),
        amount: priced.total,
        station_id: actor.station_id,
        created_by_id: actor.id
      },
      opts
    )

    {:ok, shipment}
  end
end
