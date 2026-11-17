defmodule Ex.Shipping.Payment do
  @moduledoc """
  Money taken for a Shipment. Append-only (ADR-0005): no update or destroy action, and Postgres
  rejects UPDATE and DELETE. A refund is a second row, never an edit.

  The first Payment is made with the Shipment; one refund per Shipment may follow a cancellation.
  """
  use Ash.Resource,
    otp_app: :ex,
    domain: Ex.Shipping,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "payments"
    repo Ex.Repo

    references do
      reference :shipment, on_delete: :restrict, index?: true
      reference :station, on_delete: :restrict, index?: true
      reference :created_by, on_delete: :restrict, index?: true
      reference :status_event, on_delete: :restrict, index?: true
    end

    custom_indexes do
      index [:shipment_id],
        unique: true,
        where: "kind = 'refund'",
        name: "payments_one_refund_idx"
    end

    check_constraints do
      check_constraint :amount, "payments_amount_whole_khr",
        check: "(amount).currency_code = 'KHR' AND (amount).amount = trunc((amount).amount)",
        message: "must be a whole number of riel"

      check_constraint :kind, "payments_kind_values",
        check: "kind IN ('payment','refund')",
        message: "unknown kind"

      check_constraint :method, "payments_method_values",
        check: "method IN ('cash','bank_transfer','qr')",
        message: "unknown payment method"

      check_constraint :amount, "payments_amount_sign_matches_kind",
        check:
          "(kind = 'payment' AND (amount).amount > 0) OR (kind = 'refund' AND (amount).amount < 0)",
        message: "a payment is above 0 and a refund below 0"
    end

    custom_statements do
      statement :append_only do
        up """
        CREATE TRIGGER payments_append_only
        BEFORE UPDATE OR DELETE ON payments
        FOR EACH ROW EXECUTE FUNCTION reject_change()
        """

        down "DROP TRIGGER IF EXISTS payments_append_only ON payments"
      end
    end
  end

  json_api do
    type "payment"
  end

  actions do
    defaults [:read]

    create :record do
      primary? true

      accept [
        :shipment_id,
        :kind,
        :method,
        :amount,
        :station_id,
        :created_by_id,
        :status_event_id
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Ex.Accounts.Checks.HasPermission, permission: :"shipment.read"}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      default: :payment,
      public?: true,
      constraints: [one_of: [:payment, :refund]]

    attribute :method, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:cash, :bank_transfer, :qr]]

    attribute :amount, AshMoney.Types.Money, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :shipment, Ex.Shipping.Shipment, allow_nil?: false, public?: true
    belongs_to :station, Ex.Network.Station, allow_nil?: false, public?: true
    belongs_to :created_by, Ex.Accounts.User, allow_nil?: false, public?: true
    # Set on a refund: the cancelled Status Event it belongs to.
    belongs_to :status_event, Ex.Shipping.StatusEvent, public?: true
  end
end
