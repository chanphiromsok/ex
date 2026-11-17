defmodule Ex.Shipping.Changes.DecideCancellation do
  @moduledoc """
  Approves or rejects a pending Cancellation Request (`decision: :approved | :rejected`).

  The approver must not be the requester. Approving cancels the Shipment in the same transaction (see
  `Ex.Shipping.Cancellation`) and stores the fee and refund on the request; it fails once the Shipment is
  In Transit. Rejecting keeps the decision and its reason (required).
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    decision = opts[:decision]

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      request = changeset.data

      cond do
        request.status != :pending ->
          Ash.Changeset.add_error(changeset,
            field: :status,
            message: "is already #{request.status}"
          )

        request.requested_by_id == actor.id ->
          Ash.Changeset.add_error(changeset,
            field: :requested_by_id,
            message: "a Cancellation Request must be decided by a different Supervisor"
          )

        decision == :rejected and blank?(Ash.Changeset.get_attribute(changeset, :decision_reason)) ->
          Ash.Changeset.add_error(changeset,
            field: :decision_reason,
            message: "is required to reject"
          )

        true ->
          Ash.Changeset.force_change_attributes(changeset,
            status: decision,
            decided_by_id: actor.id,
            decided_at: DateTime.utc_now()
          )
      end
    end)
    |> Ash.Changeset.after_action(fn _changeset, request ->
      if decision == :approved,
        do: Ex.Shipping.CancellationRequest.settle(request, actor),
        else: {:ok, request}
    end)
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
