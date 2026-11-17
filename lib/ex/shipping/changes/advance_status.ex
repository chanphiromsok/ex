defmodule Ex.Shipping.Changes.AdvanceStatus do
  @moduledoc """
  Moves a Shipment one step along received → in transit → arrived → collected by appending a Status
  Event. Steps cannot be skipped or repeated: the Shipment must be exactly in the `from` status.

  The Shipment row is locked while the next `seq` is worked out, so two staff pressing the same
  button at once get one new event and one clear error (the unique `(shipment_id, seq)` index is the
  backstop). Nothing is ever updated: the history only grows.

  Options: `from:` the status the Shipment must be in, `to:` the status it moves to.
  """
  use Ash.Resource.Change

  alias Ex.Shipping.{Shipment, StatusEvent}
  require Ash.Query

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      shipment_id = changeset.data.id

      # Lock the Shipment first, then read its latest event: nobody else can append in between.
      Shipment
      |> Ash.Query.filter(id == ^shipment_id)
      |> Ash.Query.lock("FOR UPDATE")
      |> Ash.read!(authorize?: false)

      latest =
        StatusEvent
        |> Ash.Query.filter(shipment_id == ^shipment_id)
        |> Ash.Query.sort(seq: :desc)
        |> Ash.Query.limit(1)
        |> Ash.read_one!(authorize?: false)

      if latest.status == opts[:from] do
        Ash.Changeset.after_action(changeset, fn _changeset, shipment ->
          Ash.create!(
            StatusEvent,
            %{
              shipment_id: shipment.id,
              seq: latest.seq + 1,
              status: opts[:to],
              station_id: actor.station_id,
              created_by_id: actor.id
            },
            authorize?: false
          )

          {:ok, shipment}
        end)
      else
        Ash.Changeset.add_error(changeset,
          field: :status,
          message:
            "must be #{label(opts[:from])} to become #{label(opts[:to])}, but it is #{label(latest.status)}"
        )
      end
    end)
  end

  defp label(status), do: Ex.Shipping.Status.label_en(status)
end
