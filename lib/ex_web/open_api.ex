defmodule ExWeb.OpenApi do
  @moduledoc """
  Adds the page intro, tag descriptions and public-endpoint markers to the generated OpenAPI spec
  that Scalar renders at `/api/docs`.
  """

  @public_paths ["/users/sign-in", "/users/refresh"]

  @tag_descriptions %{
    "user" => "Accounts, roles, sessions and tokens.",
    "location" => "Cities and provinces a Station is in.",
    "station" => "Offices where staff receive and hand over Shipments.",
    "permission" => "The permissions a role can be given."
  }

  def modify(spec, _conn, _opts) do
    %{
      spec
      | info: %{spec.info | description: intro()},
        tags: tags(spec),
        paths: Map.new(spec.paths, &mark_public/1)
    }
  end

  defp intro do
    """
    Express goods by bus, from a Station to a Station.

    **Getting started:** `POST /users/sign-in` with an email and password, then send the returned
    token as `Authorization: Bearer <token>`. Access tokens last one hour; renew them with
    `POST /users/refresh`.
    """
  end

  # AshJsonApi leaves `spec.tags` empty, so build one per tag used by an operation.
  defp tags(spec) do
    spec.paths
    |> Enum.flat_map(fn {_path, item} -> operations(item) end)
    |> Enum.flat_map(&(&1.tags || []))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&%OpenApiSpex.Tag{name: &1, description: Map.get(@tag_descriptions, &1)})
  end

  defp operations(item) do
    [:get, :post, :patch, :put, :delete] |> Enum.map(&Map.get(item, &1)) |> Enum.reject(&is_nil/1)
  end

  # Sign-in and refresh need no bearer token, so drop the spec-wide requirement for them.
  defp mark_public({path, item}) do
    if Enum.any?(@public_paths, &String.ends_with?(path, &1)) do
      {path, %{item | post: %{item.post | security: []}}}
    else
      {path, item}
    end
  end
end
