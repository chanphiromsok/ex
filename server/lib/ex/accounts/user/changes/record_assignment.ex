defmodule Ex.Accounts.User.Changes.RecordAssignment do
  @moduledoc "Appends a UserAssignmentChange in the same transaction as the User create or update."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      Ex.Accounts.UserAssignmentChange
      |> Ash.Changeset.for_create(:record, %{
        user_id: user.id,
        role: user.role,
        station_id: user.station_id,
        changed_by_id: context.actor && context.actor.id
      })
      |> Ash.create!(authorize?: false)

      {:ok, user}
    end)
  end
end
