defmodule Ex.Pricing.Changes.LogPrice do
  @moduledoc """
  After the action succeeds, appends a `Ex.Pricing.PriceChange` for the price it set.

  Runs inside the action's transaction, so a price and its log row are saved together or not at all.

  Options: `:kind` (the PriceChange kind), `:attribute` (the money attribute that was set) and,
  for Size Classes and Sale Items, `:foreign_key` (`:size_class_id` or `:sale_item_id`).
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      attrs =
        %{
          kind: opts[:kind],
          price: Map.fetch!(record, opts[:attribute]),
          changed_by_id: actor_id(context)
        }
        |> put_foreign_key(opts[:foreign_key], record)

      Ash.create!(Ex.Pricing.PriceChange, attrs, authorize?: false)
      {:ok, record}
    end)
  end

  defp put_foreign_key(attrs, nil, _record), do: attrs
  defp put_foreign_key(attrs, key, record), do: Map.put(attrs, key, record.id)

  defp actor_id(%{actor: %{id: id}}), do: id
  defp actor_id(_), do: nil
end
