defmodule Ex.Shipping.Checks.AtShipmentStation do
  @moduledoc """
  For a create action that has a `shipment_id`: passes when the actor works at that Shipment's origin or
  destination Station. Usage: `{Ex.Shipping.Checks.AtShipmentStation, side: :origin}`.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts), do: "actor works at the Shipment's #{opts[:side]} Station"

  @impl true
  def match?(%{station_id: station_id}, %{changeset: %Ash.Changeset{} = changeset}, opts)
      when not is_nil(station_id) do
    with shipment_id when not is_nil(shipment_id) <-
           Ash.Changeset.get_attribute(changeset, :shipment_id),
         {:ok, shipment} <- Ash.get(Ex.Shipping.Shipment, shipment_id, authorize?: false) do
      station_id == Map.fetch!(shipment, :"#{opts[:side]}_station_id")
    else
      _ -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
