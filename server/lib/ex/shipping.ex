defmodule Ex.Shipping do
  @moduledoc "Shipments: what a Sender hands over at a Station, what it costs, and what happens to it."
  use Ash.Domain, otp_app: :ex, extensions: [AshJsonApi.Domain]

  resources do
    resource Ex.Shipping.Shipment
    resource Ex.Shipping.Parcel
    resource Ex.Shipping.ShipmentSaleItem
    resource Ex.Shipping.StatusEvent
    resource Ex.Shipping.Payment
    resource Ex.Shipping.ShipmentNote
    resource Ex.Shipping.ReceiverCorrection
    resource Ex.Shipping.CancellationRequest
    resource Ex.Shipping.Incident
    resource Ex.Shipping.Manifest
    resource Ex.Shipping.Report
  end
end
