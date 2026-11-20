defmodule Ex.Pricing.Changes.LogSetting do
  @moduledoc """
  After the action succeeds, appends an `Ex.Pricing.SettingChange` recording what was set and by whom.
  Same transaction as the change itself, so a setting and its log row are saved together or not at all.

  Option `:kind` is `:cancellation_fee`, `:station_cancellation_approval` or `:station_overdue_threshold`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      attrs =
        case opts[:kind] do
          :cancellation_fee ->
            %{percent: record.percent, cap: record.cap}

          :station_cancellation_approval ->
            %{station_id: record.id, requires_approval: record.cancellation_requires_approval}

          :station_overdue_threshold ->
            %{station_id: record.id, days: record.overdue_threshold_days}
        end

      Ash.create!(
        Ex.Pricing.SettingChange,
        Map.merge(attrs, %{kind: opts[:kind], changed_by_id: actor_id(context)}),
        authorize?: false
      )

      {:ok, record}
    end)
  end

  defp actor_id(%{actor: %{id: id}}), do: id
  defp actor_id(_), do: nil
end
