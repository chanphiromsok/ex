defmodule Ex.Shipping.Changes.StampActor do
  @moduledoc "Records who did it and where: sets `created_by_id` and `station_id` from the signed-in user."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: actor}) when not is_nil(actor) do
    changeset
    |> Ash.Changeset.force_change_attribute(:created_by_id, actor.id)
    |> Ash.Changeset.force_change_attribute(:station_id, actor.station_id)
  end

  def change(changeset, _opts, _context), do: changeset
end
