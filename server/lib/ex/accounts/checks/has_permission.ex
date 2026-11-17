defmodule Ex.Accounts.Checks.HasPermission do
  @moduledoc "Passes when the actor effectively holds the Permission. Usage: `authorize_if {Ex.Accounts.Checks.HasPermission, permission: :\"user.manage\"}`"
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts), do: "actor has permission #{opts[:permission]}"

  @impl true
  def match?(%Ex.Accounts.User{} = actor, _context, opts) do
    permissions =
      case actor.permissions do
        %Ash.NotLoaded{} -> Ash.load!(actor, :permissions, authorize?: false).permissions
        loaded -> loaded
      end

    to_string(opts[:permission]) in permissions
  end

  def match?(_actor, _context, _opts), do: false
end
