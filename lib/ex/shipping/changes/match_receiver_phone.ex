defmodule Ex.Shipping.Changes.MatchReceiverPhone do
  @moduledoc "Collection only goes ahead when the phone number given by the customer matches the Receiver phone (the latest Receiver Correction, if any)."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    given = Ash.Changeset.get_argument(changeset, :receiver_phone)
    changeset = Ash.Changeset.load(changeset, :current_receiver_phone)

    case Ex.Shipping.Phone.normalize(given) do
      {:ok, phone} when phone == changeset.data.current_receiver_phone ->
        changeset

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :receiver_phone,
          message: "does not match the Receiver phone"
        )
    end
  end
end
