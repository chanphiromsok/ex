defmodule Ex.Repo.Migrations.DescribePermissions do
  @moduledoc "Gives every Permission a plain-language description of what it lets someone do."

  use Ecto.Migration

  @descriptions %{
    "shipment.create" => "Receive a parcel from a Sender at their own Station, work out the price and take Payment. Creates the Invoice.",
    "shipment.read" => "Look up any Shipment by Invoice Number or phone number, at any Station. Read only.",
    "shipment.mark_in_transit" => "Record that a Shipment has left their own Station on the bus (scan it onto a Manifest and mark the bus as left).",
    "shipment.mark_arrived" => "Record that a Shipment has reached their own Station, by scanning it off the bus and closing the Manifest.",
    "shipment.collect" => "Hand a Shipment to its Receiver at their own Station, after checking the Receiver's phone number.",
    "shipment.add_note" => "Write a Note on a Shipment, for example a message for the next Station.",
    "cancellation.request" => "Ask to cancel a Shipment that is still Received, at the origin Station. A Supervisor may need to approve it.",
    "cancellation.approve" => "Approve or reject a cancellation request from their own Station. Approving cancels the Shipment and may refund the Sender.",
    "receiver.correct" => "Fix the Receiver's name or phone on a Shipment after the bus has left, with a written reason.",
    "incident.report" => "Report a problem with a Shipment in transit or arrived, such as damaged, lost or wrong parcel.",
    "incident.resolve" => "Close an open Incident by writing how it was resolved.",
    "report.cash" => "View the cash report: the money taken and refunded.",
    "report.cancellation" => "View the cancellation report: which Shipments were cancelled, why, and the fees kept.",
    "price.manage" => "Change the price per kg, the Size Class and Sale Item prices, and the Cancellation Fee. Every change is logged.",
    "reference_data.manage" => "Add and edit Locations, Stations and Routes, and link Stations to the external schedule.",
    "station_setting.manage" => "Change each Station's settings, such as whether cancellations need approval and when a Shipment counts as overdue.",
    "user.manage" => "Create users and change their role, Station and password."
  }

  def up do
    for {name, text} <- @descriptions do
      execute("UPDATE permissions SET description = '#{String.replace(text, "'", "''")}' WHERE name = '#{name}'")
    end
  end

  def down, do: :ok
end
