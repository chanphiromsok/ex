defmodule Ex.Shipping.Changes.ScanManifest do
  @moduledoc """
  One scan of a Shipment's Invoice Number against a Manifest.

  * Manifest open (loading, origin Station): puts the Shipment on the Manifest. It must be Received, going
    to the Manifest's Station pair, and on no other Manifest. Scanning it again is harmless.
  * Manifest departed (unloading, destination Station): the Shipment must be on this Manifest; it is marked
    Arrived. Scanning it again is harmless. A Shipment that is not on the Manifest is refused (unexpected).

  The Shipment and the Manifest rows are locked while checked, so two scans at once cannot put one
  Shipment on two Manifests, or load onto a Manifest that is departing.
  """
  use Ash.Resource.Change

  alias Ex.Accounts.Checks.HasPermission
  alias Ex.Shipping.{Manifest, Shipment, Status}
  require Ash.Query

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      invoice_no = Ash.Changeset.get_argument(changeset, :invoice_no)

      manifest =
        Manifest
        |> Ash.Query.filter(id == ^changeset.data.id)
        |> Ash.Query.lock("FOR UPDATE")
        |> Ash.read_one!(authorize?: false)

      shipment =
        Shipment
        |> Ash.Query.filter(invoice_no == ^invoice_no)
        |> Ash.Query.lock("FOR UPDATE")
        |> Ash.read_one!(authorize?: false)

      case scan(manifest.status, manifest, shipment, invoice_no, actor) do
        :ok ->
          changeset

        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :invoice_no, message: message)
      end
    end)
  end

  defp scan(:arrived, _manifest, _shipment, _no, _actor),
    do: {:error, "this Manifest has already arrived"}

  defp scan(_status, _manifest, nil, no, _actor),
    do: {:error, "there is no Shipment with Invoice Number #{no}"}

  defp scan(:open, manifest, shipment, no, actor) do
    with :ok <-
           at_station(actor, manifest.origin_station_id, "load Shipments at the origin Station"),
         :ok <- permitted(actor, :"shipment.mark_in_transit"),
         :ok <- same_stations(manifest, shipment, no),
         :ok <- loadable(shipment, manifest, no) do
      if shipment.manifest_id == manifest.id do
        :ok
      else
        Ash.update!(shipment, %{manifest_id: manifest.id},
          action: :set_manifest,
          authorize?: false
        )

        :ok
      end
    end
  end

  defp scan(:departed, manifest, shipment, no, actor) do
    with :ok <-
           at_station(
             actor,
             manifest.destination_station_id,
             "unload Shipments at the destination Station"
           ),
         :ok <- permitted(actor, :"shipment.mark_arrived") do
      cond do
        shipment.manifest_id != manifest.id ->
          {:error, "Shipment #{no} is not on this Manifest"}

        shipment.status in [:arrived, :collected] ->
          :ok

        shipment.status == :in_transit ->
          case Ash.update(shipment, %{}, action: :mark_arrived, actor: actor) do
            {:ok, _} -> :ok
            {:error, error} -> {:error, Exception.message(error)}
          end

        true ->
          {:error, "Shipment #{no} is #{Status.label_en(shipment.status)}, not In transit"}
      end
    end
  end

  defp same_stations(manifest, shipment, no) do
    if shipment.origin_station_id == manifest.origin_station_id and
         shipment.destination_station_id == manifest.destination_station_id,
       do: :ok,
       else: {:error, "Shipment #{no} is not going from and to this Manifest's Stations"}
  end

  defp loadable(shipment, manifest, no) do
    cond do
      shipment.status != :received ->
        {:error,
         "Shipment #{no} is #{Status.label_en(shipment.status)}; only Received Shipments can be loaded"}

      shipment.manifest_id not in [nil, manifest.id] ->
        {:error, "Shipment #{no} is already on another Manifest"}

      true ->
        :ok
    end
  end

  defp at_station(%{station_id: id}, id, _what) when not is_nil(id), do: :ok
  defp at_station(_actor, _id, what), do: {:error, "you can only #{what}"}

  defp permitted(actor, permission) do
    if HasPermission.match?(actor, nil, permission: permission),
      do: :ok,
      else: {:error, "you do not have the #{permission} permission"}
  end
end
