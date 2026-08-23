defmodule HoloMap.Spec do
  @moduledoc """
  Turns Elixir-flavoured component props into MapLibre style-specification maps.

  The MapLibre style specification is not written in one casing. Paint and
  layout properties are kebab-case (`fill-color`, `text-allow-overlap`), some
  layer keys are kebab-case (`source-layer`), and several source keys are
  camelCase (`tileSize`, `promoteId`, `clusterMaxZoom`). A single mechanical
  rule would get one of those groups wrong, so this module keeps two distinct
  paths:

    * `dasherize/1`, for paint and layout maps, where underscore-to-hyphen is
      genuinely the universal rule.
    * `take/2`, for everything else, where each prop is mapped to its exact
      specification key through an explicit table declared by the component.

  Both paths drop `nil` values instead of emitting `null`. MapLibre treats an
  explicit `null` as "reset to the default", which is not what an unset prop
  means, and an absent key leaves the property alone.

  ## Escape hatch

  String keys always pass through untouched. A property this library has not
  caught up with is still reachable:

      paint={%{"fill-color" => "#f00", "some-new-property" => 1}}
  """

  @typedoc "A MapLibre style specification fragment, ready for JSON encoding."
  @type t :: %{optional(String.t()) => term()}

  @typedoc "A longitude/latitude pair in any of the accepted input shapes."
  @type lng_lat :: {number(), number()} | [number()] | %{lng: number(), lat: number()}

  @doc """
  Converts a paint or layout map into specification keys.

  Atom keys are dasherized; string keys pass through verbatim; `nil` values are
  dropped.

      iex> HoloMap.Spec.dasherize(%{fill_color: "#f00", fill_opacity: nil})
      %{"fill-color" => "#f00"}

      iex> HoloMap.Spec.dasherize(%{"text-allow-overlap" => true})
      %{"text-allow-overlap" => true}

      iex> HoloMap.Spec.dasherize(nil)
      %{}
  """
  @spec dasherize(map() | nil) :: t()
  def dasherize(nil), do: %{}

  def dasherize(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> {dasherize_key(key), value} end)
    |> Enum.into(%{})
  end

  @doc """
  Builds a specification map by pulling props through an explicit key table.

  `table` is a keyword list of `{prop_name, specification_key}`. Props that are
  absent or `nil` are skipped, so a component can declare its full surface once
  and let the user set only what they need.

      iex> props = %{source_layer: "water", min_zoom: 4, max_zoom: nil}
      iex> table = [source_layer: "source-layer", min_zoom: "minzoom", max_zoom: "maxzoom"]
      iex> HoloMap.Spec.take(props, table)
      %{"source-layer" => "water", "minzoom" => 4}
  """
  @spec take(map(), keyword(String.t())) :: t()
  def take(props, table) when is_map(props) and is_list(table) do
    Enum.reduce(table, %{}, fn {prop_name, spec_key}, acc ->
      case Map.get(props, prop_name) do
        nil -> acc
        value -> Map.put(acc, spec_key, value)
      end
    end)
  end

  @doc """
  Merges specification fragments left to right, with later keys winning.

  `nil` fragments are ignored, which lets a component pipe optional sections
  together without branching.

      iex> HoloMap.Spec.merge([%{"a" => 1}, nil, %{"a" => 2, "b" => 3}])
      %{"a" => 2, "b" => 3}
  """
  @spec merge([t() | nil]) :: t()
  def merge(fragments) when is_list(fragments) do
    Enum.reduce(fragments, %{}, fn
      nil, acc -> acc
      fragment, acc when is_map(fragment) -> Map.merge(acc, fragment)
    end)
  end

  @doc """
  Normalises a longitude/latitude pair into the `[lng, lat]` list MapLibre uses.

  Tuples read well in templates but have no JSON representation, so they are
  converted here rather than at the encoder.

      iex> HoloMap.Spec.lng_lat({-70.66, 19.45})
      [-70.66, 19.45]

      iex> HoloMap.Spec.lng_lat(%{lng: -70.66, lat: 19.45})
      [-70.66, 19.45]

      iex> HoloMap.Spec.lng_lat([-70.66, 19.45])
      [-70.66, 19.45]

      iex> HoloMap.Spec.lng_lat(nil)
      nil
  """
  @spec lng_lat(lng_lat() | nil) :: [number()] | nil
  def lng_lat(nil), do: nil
  def lng_lat({lng, lat}) when is_number(lng) and is_number(lat), do: [lng, lat]
  def lng_lat([lng, lat]) when is_number(lng) and is_number(lat), do: [lng, lat]
  def lng_lat(%{lng: lng, lat: lat}) when is_number(lng) and is_number(lat), do: [lng, lat]

  def lng_lat(other) do
    raise ArgumentError,
          "expected a {lng, lat} tuple, a [lng, lat] list or a %{lng: _, lat: _} map, " <>
            "got: #{inspect(other)}"
  end

  @doc """
  Normalises a bounding box into MapLibre's `[[west, south], [east, north]]`.

  Accepts a pair of corners in tuple or list form, or the flat
  `[west, south, east, north]` shape that GeoJSON bounding boxes use.

      iex> HoloMap.Spec.bounds({{-71.0, 19.0}, {-70.0, 20.0}})
      [[-71.0, 19.0], [-70.0, 20.0]]

      iex> HoloMap.Spec.bounds([-71.0, 19.0, -70.0, 20.0])
      [[-71.0, 19.0], [-70.0, 20.0]]

      iex> HoloMap.Spec.bounds(nil)
      nil
  """
  @spec bounds(term()) :: [[number()]] | nil
  def bounds(nil), do: nil

  def bounds({south_west, north_east}) do
    [lng_lat(south_west), lng_lat(north_east)]
  end

  def bounds([west, south, east, north])
      when is_number(west) and is_number(south) and is_number(east) and is_number(north) do
    [[west, south], [east, north]]
  end

  def bounds([south_west, north_east]) do
    [lng_lat(south_west), lng_lat(north_east)]
  end

  def bounds(other) do
    raise ArgumentError,
          "expected a {south_west, north_east} pair or a [west, south, east, north] list, " <>
            "got: #{inspect(other)}"
  end

  @doc """
  Coerces a boolean prop written as a bare attribute.

  In a HOLO template a bare attribute is an empty *string*, not `true`, so
  `<HoloMap.Source.GeoJSON cluster />` would otherwise hand MapLibre `""` and
  fail style validation with `boolean expected, string found`. Writing the
  attribute at all means "on", which is what every component framework's bare
  attribute means, so that is what it becomes.

      iex> HoloMap.Spec.boolean("")
      true

      iex> HoloMap.Spec.boolean(true)
      true

      iex> HoloMap.Spec.boolean("false")
      false

      iex> HoloMap.Spec.boolean(nil)
      nil
  """
  @spec boolean(term()) :: boolean() | nil
  def boolean(nil), do: nil
  def boolean(true), do: true
  def boolean(false), do: false
  def boolean(""), do: true
  def boolean("true"), do: true
  def boolean("false"), do: false

  def boolean(other) do
    raise ArgumentError,
          "expected a boolean, got: #{inspect(other)}"
  end

  @doc """
  Applies `boolean/1` to the listed keys of a props map.

  Components declare their own boolean props rather than coercing everything,
  because an empty string is a legitimate value for a text prop and must not
  silently become `true` there.

      iex> HoloMap.Spec.booleans(%{cluster: "", radius: 50}, [:cluster])
      %{cluster: true, radius: 50}
  """
  @spec booleans(map(), [atom()]) :: map()
  def booleans(props, keys) when is_map(props) and is_list(keys) do
    # `Map.fetch/2` is avoided deliberately: in Hologram 0.11.0 the client-side
    # port of `:maps.find/2` returns the bare value instead of `{:ok, value}`,
    # so the usual fetch-and-match reduces to a CaseClauseError in the browser
    # while working perfectly on the server. `Map.get/3` with a sentinel behaves
    # the same on both sides.
    Enum.reduce(keys, props, fn key, acc ->
      case Map.get(acc, key, :__holo_map_absent__) do
        :__holo_map_absent__ -> acc
        value -> Map.put(acc, key, boolean(value))
      end
    end)
  end

  defp dasherize_key(key) when is_binary(key), do: key

  defp dasherize_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp dasherize_key(key) do
    raise ArgumentError,
          "expected a paint/layout property name as an atom or string, got: #{inspect(key)}"
  end
end
