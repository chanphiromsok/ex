defmodule Ex.Shipping.Changes.NormalizePhones do
  @moduledoc "Rewrites the Sender and Receiver phones to 855… form, or rejects them (see `Ex.Shipping.Phone`)."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Enum.reduce([:sender_phone, :receiver_phone], changeset, fn field, changeset ->
      case Ash.Changeset.fetch_change(changeset, field) do
        {:ok, value} ->
          case Ex.Shipping.Phone.normalize(value) do
            {:ok, normalised} ->
              Ash.Changeset.force_change_attribute(changeset, field, normalised)

            :error ->
              Ash.Changeset.add_error(changeset,
                field: field,
                message: "is not a valid Cambodian phone number"
              )
          end

        :error ->
          changeset
      end
    end)
  end
end
