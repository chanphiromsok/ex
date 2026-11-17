defmodule Ex.Shipping.Changes.MoveManifest do
  @moduledoc """
  Departs or arrives a whole Manifest.

  * `to: :departed` (origin Station): every Received Shipment on it becomes In transit, through the normal
    Status Events. Shipments cancelled, or with a pending Cancellation Request, since loading are taken off. It needs at least one Shipment.
  * `to: :arrived` (destination Station): closes the Manifest. Shipments not scanned are left In transit and
    show as remaining, so the missing ones are visible.
  """
  use Ash.Resource.Change

  alias Ex.Accounts.Checks.HasPermission
  alias Ex.Shipping.{Manifest, Shipment}
  require Ash.Query

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      manifest =
        Manifest
        |> Ash.Query.filter(id == ^changeset.data.id)
        |> Ash.Query.lock("FOR UPDATE")
        |> Ash.read_one!(authorize?: false)

      case move(opts[:to], manifest, actor) do
        :ok ->
          changeset
          |> Ash.Changeset.force_change_attribute(:status, opts[:to])
          |> Ash.Changeset.force_change_attribute(:"#{opts[:to]}_at", DateTime.utc_now())

        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :status, message: message)
      end
    end)
  end

  defp move(:departed, manifest, actor) do
    with :ok <- state(manifest, :open, "is not open"),
         :ok <-
           at_station(
             actor,
             manifest.origin_station_id,
             "depart a Manifest at its origin Station"
           ),
         :ok <- permitted(actor, :"shipment.mark_in_transit") do
      shipments =
        Shipment
        |> Ash.Query.filter(manifest_id == ^manifest.id)
        |> Ash.Query.lock("FOR UPDATE")
        |> Ash.read!(authorize?: false)

      {received, rest} =
        Enum.split_with(
          shipments,
          &(&1.status == :received and
              not Ex.Shipping.Changes.ScanManifest.pending_cancellation?(&1))
        )

      Enum.each(
        rest,
        &Ash.update!(&1, %{manifest_id: nil}, action: :set_manifest, authorize?: false)
      )

      if received == [] do
        {:error, "scan at least one Shipment before departing"}
      else
        Enum.reduce_while(received, :ok, fn shipment, :ok ->
          case Ash.update(shipment, %{}, action: :mark_in_transit, actor: actor) do
            {:ok, _} ->
              {:cont, :ok}

            {:error, error} ->
              {:halt, {:error, "Shipment #{shipment.invoice_no}: #{Exception.message(error)}"}}
          end
        end)
      end
    end
  end

  defp move(:arrived, manifest, actor) do
    with :ok <- state(manifest, :departed, "has not departed"),
         :ok <-
           at_station(
             actor,
             manifest.destination_station_id,
             "close a Manifest at its destination Station"
           ),
         do: permitted(actor, :"shipment.mark_arrived")
  end

  defp state(%{status: status}, status, _message), do: :ok
  defp state(_manifest, _wanted, message), do: {:error, "this Manifest #{message}"}

  defp at_station(%{station_id: id}, id, _what) when not is_nil(id), do: :ok
  defp at_station(_actor, _id, what), do: {:error, "you can only #{what}"}

  defp permitted(actor, permission) do
    if HasPermission.match?(actor, nil, permission: permission),
      do: :ok,
      else: {:error, "you do not have the #{permission} permission"}
  end
end
