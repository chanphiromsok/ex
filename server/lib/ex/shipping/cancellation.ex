defmodule Ex.Shipping.Cancellation do
  @moduledoc """
  Cancels a Received Shipment: appends the `cancelled` Status Event at the origin Station and records ONE
  refund Payment for what was paid minus the Cancellation Fee.

  Fee = min(Shipment Total x percent, cap), rounded half-up to whole riel, and never more than what was
  paid. The refund uses the first Payment's method and is skipped when it would be 0. Runs inside the
  caller's transaction; the Shipment row is locked so two cancellations or a cancel racing an "in transit"
  cannot both win (the once-per-Shipment indexes are the backstop).
  """
  alias Ex.Shipping.{Payment, Shipment, StatusEvent}
  require Ash.Query

  @doc "Cancels the Shipment for `actor`, with `reason`. Returns `{:ok, %{fee: Money, refund: Money}}` or `{:error, message}`."
  def perform(shipment_id, reason, actor) do
    shipment = lock(shipment_id)
    latest = latest_event(shipment_id)

    if latest.status == :received do
      event =
        Ash.create!(
          StatusEvent,
          %{
            shipment_id: shipment_id,
            seq: latest.seq + 1,
            status: :cancelled,
            reason: reason,
            station_id: shipment.origin_station_id,
            created_by_id: actor.id
          },
          authorize?: false
        )

      payments =
        Ash.read!(Payment |> Ash.Query.filter(shipment_id == ^shipment_id), authorize?: false)

      paid = Enum.reduce(payments, Money.new(:KHR, 0), &Money.add!(&1.amount, &2))
      fee = fee(shipment.shipment_total, paid)
      refund = Money.sub!(paid, fee)
      refund_payment(shipment, payments, refund, event)

      {:ok, %{fee: fee, refund: refund}}
    else
      {:error,
       "must be Received to be cancelled, but it is #{Ex.Shipping.Status.label_en(latest.status)}"}
    end
  end

  @doc "The Cancellation Fee for a Shipment Total, capped at `paid`."
  def fee(total, paid) do
    setting =
      Ash.read_one!(Ex.Pricing.CancellationFeeSetting, action: :current, authorize?: false)

    percent = (setting && setting.percent) || 0

    amount =
      total.amount
      |> Decimal.mult(percent)
      |> Decimal.div(100)
      |> Decimal.round(0, :half_up)

    fee = Money.new(:KHR, amount)
    fee = if setting && setting.cap, do: min_money(fee, setting.cap), else: fee
    min_money(fee, paid)
  end

  defp min_money(a, b), do: if(Money.compare!(a, b) == :gt, do: b, else: a)

  defp refund_payment(shipment, payments, refund, event) do
    if Money.positive?(refund) do
      first = Enum.min_by(payments, & &1.inserted_at, DateTime)

      Ash.create!(
        Payment,
        %{
          shipment_id: shipment.id,
          kind: :refund,
          method: first.method,
          amount: Money.mult!(refund, -1),
          station_id: shipment.origin_station_id,
          created_by_id: first.created_by_id,
          status_event_id: event.id
        },
        authorize?: false
      )
    end
  end

  defp lock(shipment_id) do
    Shipment
    |> Ash.Query.filter(id == ^shipment_id)
    |> Ash.Query.lock("FOR UPDATE")
    |> Ash.read_one!(authorize?: false)
  end

  defp latest_event(shipment_id) do
    StatusEvent
    |> Ash.Query.filter(shipment_id == ^shipment_id)
    |> Ash.Query.sort(seq: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end
end
