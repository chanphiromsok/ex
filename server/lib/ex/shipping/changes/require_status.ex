defmodule Ex.Shipping.Changes.RequireStatus do
  @moduledoc "Only lets the action through while the Shipment's current status is one of `statuses`."
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      shipment_id = Ash.Changeset.get_attribute(changeset, :shipment_id)

      status =
        Ex.Shipping.StatusEvent
        |> Ash.Query.filter(shipment_id == ^shipment_id)
        |> Ash.Query.sort(seq: :desc)
        |> Ash.Query.limit(1)
        |> Ash.read_one!(authorize?: false)
        |> then(&(&1 && &1.status))

      if status in opts[:statuses] do
        changeset
      else
        Ash.Changeset.add_error(changeset,
          field: :shipment_id,
          message:
            "must be #{Enum.map_join(opts[:statuses], " or ", &Ex.Shipping.Status.label_en/1)}, but is #{status && Ex.Shipping.Status.label_en(status)}"
        )
      end
    end)
  end
end
