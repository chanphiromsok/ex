defmodule Ex.Accounts.Permission do
  @moduledoc "The fixed list of Permissions. Adding one needs a deploy, because code must check it."
  use Ash.Type.Enum,
    values: [
      :"shipment.create",
      :"shipment.read",
      :"shipment.mark_in_transit",
      :"shipment.mark_arrived",
      :"shipment.collect",
      :"shipment.add_note",
      :"cancellation.request",
      :"cancellation.approve",
      :"receiver.correct",
      :"incident.report",
      :"incident.resolve",
      :"report.cash",
      :"report.cancellation",
      :"price.manage",
      :"reference_data.manage",
      :"station_setting.manage",
      :"user.manage"
    ]
end
