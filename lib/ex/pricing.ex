defmodule Ex.Pricing do
  @moduledoc "What Shipments cost: Size Classes, Sale Items, the price per kg and the log of every price set."
  use Ash.Domain,
    otp_app: :ex,
    extensions: [AshJsonApi.Domain]

  resources do
    resource Ex.Pricing.SizeClass
    resource Ex.Pricing.SaleItem
    resource Ex.Pricing.PriceChange
  end
end
