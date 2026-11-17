defmodule Ex.Shipping.CancellationRequest do
  @moduledoc """
  A request to cancel a Received Shipment, made by origin staff. Where the origin Station requires approval
  (the default) it stays `pending` until a different origin Supervisor approves or rejects it; otherwise it is
  approved on the spot. Approval cancels the Shipment and refunds what was paid minus the Cancellation Fee.
  A rejected request keeps its decision and reason. Once a Shipment is In Transit it can no longer be cancelled.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  alias Ex.Shipping.{Cancellation, Shipment}
  require Ash.Query

  postgres do
    table "cancellation_requests"
    repo Ex.Repo

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :station, on_delete: :restrict, index?: true
      reference :requested_by, on_delete: :restrict, index?: true
      reference :decided_by, on_delete: :restrict, index?: true
    end

    custom_indexes do
      # A Shipment has at most one open or approved Cancellation Request; rejected ones stay as history.
      index [:shipment_id],
        unique: true,
        where: "status IN ('pending', 'approved')",
        name: "cancellation_requests_open_idx"
    end
  end

  json_api do
    type "cancellation-request"

    routes do
      base "/cancellation-requests"

      index :read do
        description "Lists Cancellation Requests; use `filter[status]=pending` for the Supervisor's queue. Needs `shipment.read`."
      end

      post :request do
        description """
        Asks to cancel a Received Shipment, with a reason. Needs `cancellation.request`, at the origin Station.
        Where that Station does not require approval, the Shipment is cancelled and refunded straight away.
        """
      end

      patch :approve do
        route "/:id/approve"

        description """
        Approves a pending request: cancels the Shipment and refunds paid minus the Cancellation Fee. Needs
        `cancellation.approve` at the origin Station, and must not be the person who asked.
        """
      end

      patch :reject do
        route "/:id/reject"

        description "Rejects a pending request; `decision_reason` is required. Same rights as approving."
      end
    end
  end

  actions do
    defaults [:read]

    create :request do
      primary? true
      accept [:shipment_id, :reason]
      change &__MODULE__.prepare_request/2
    end

    update :approve do
      require_atomic? false
      accept []
      change {Ex.Shipping.Changes.DecideCancellation, decision: :approved}
    end

    update :reject do
      require_atomic? false
      accept [:decision_reason]
      change {Ex.Shipping.Changes.DecideCancellation, decision: :rejected}
    end

    update :record_result do
      accept [:fee, :refund_amount]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end

    policy action(:request) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"cancellation.request"}
    end

    policy action(:request) do
      authorize_if {Ex.Shipping.Checks.AtShipmentStation, side: :origin}
    end

    policy action([:approve, :reject]) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"cancellation.approve"}
    end

    policy action([:approve, :reject]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(station_id == ^actor(:station_id))
    end

    policy action(:record_result) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :reason, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 500]

    attribute :status, :atom,
      allow_nil?: false,
      default: :pending,
      public?: true,
      writable?: false,
      constraints: [one_of: [:pending, :approved, :rejected]]

    attribute :decision_reason, :string, public?: true, constraints: [max_length: 500]
    attribute :decided_at, :utc_datetime_usec, public?: true, writable?: false
    attribute :fee, AshMoney.Types.Money, public?: true
    attribute :refund_amount, AshMoney.Types.Money, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :shipment, Shipment, allow_nil?: false, public?: true
    # The Shipment's origin Station: the only Station that can decide the request.
    belongs_to :station, Ex.Network.Station, allow_nil?: false, public?: true

    belongs_to :requested_by, Ex.Accounts.User,
      allow_nil?: false,
      public?: true,
      source_attribute: :requested_by_id

    belongs_to :decided_by, Ex.Accounts.User, public?: true
  end

  @doc false
  # Locks the Shipment, checks it can still be cancelled, and cancels at once when the Station needs no approval.
  def prepare_request(changeset, %{actor: actor}) do
    changeset
    |> Ash.Changeset.force_change_attribute(:requested_by_id, actor.id)
    |> Ash.Changeset.before_action(fn changeset ->
      shipment_id = Ash.Changeset.get_attribute(changeset, :shipment_id)

      shipment =
        Shipment
        |> Ash.Query.filter(id == ^shipment_id)
        |> Ash.Query.lock("FOR UPDATE")
        |> Ash.Query.load([:status])
        |> Ash.read_one!(authorize?: false)

      open? =
        __MODULE__
        |> Ash.Query.filter(shipment_id == ^shipment_id and status in [:pending, :approved])
        |> Ash.exists?(authorize?: false)

      cond do
        shipment.status != :received ->
          Ash.Changeset.add_error(changeset,
            field: :shipment_id,
            message:
              "must be Received to be cancelled, but is #{Ex.Shipping.Status.label_en(shipment.status)}"
          )

        open? ->
          Ash.Changeset.add_error(changeset,
            field: :shipment_id,
            message: "already has a Cancellation Request"
          )

        true ->
          station = Ash.get!(Ex.Network.Station, shipment.origin_station_id, authorize?: false)

          changeset
          |> Ash.Changeset.force_change_attribute(:station_id, shipment.origin_station_id)
          |> maybe_decide_now(station, actor)
      end
    end)
    |> Ash.Changeset.after_action(fn changeset, request ->
      if request.status == :approved and is_nil(request.fee) do
        settle(request, actor, Ash.Changeset.get_attribute(changeset, :reason))
      else
        {:ok, request}
      end
    end)
  end

  defp maybe_decide_now(changeset, %{cancellation_requires_approval: true}, _actor), do: changeset

  defp maybe_decide_now(changeset, _station, actor) do
    Ash.Changeset.force_change_attributes(changeset,
      status: :approved,
      decided_by_id: actor.id,
      decided_at: DateTime.utc_now()
    )
  end

  @doc "Cancels the request's Shipment and stores the fee and refund on the request."
  def settle(request, actor, reason \\ nil) do
    case Cancellation.perform(request.shipment_id, reason || request.reason, actor) do
      {:ok, %{fee: fee, refund: refund}} ->
        {:ok,
         Ash.update!(request, %{fee: fee, refund_amount: refund},
           action: :record_result,
           authorize?: false
         )}

      {:error, message} ->
        {:error,
         Ash.Error.Changes.InvalidAttribute.exception(field: :shipment_id, message: message)}
    end
  end
end
