defmodule HoloMap.Def do
  @moduledoc """
  Shared plumbing for the definition components nested inside a `HoloMap.Map`.

  Every child of a map — a source, a layer, a marker, a control — renders the
  same shape: one empty element carrying its specification as JSON in data
  attributes. The browser reconciler reads those attributes and does the actual
  MapLibre work. This module holds the pieces that shape is built from.

  ## The attribute protocol

  | Attribute | Meaning |
  | --------- | ------- |
  | `data-hm` | The kind of definition: `source`, `layer`, `marker`, `popup`, `control`, `terrain`, `sky` |
  | `data-hm-key` | Identity. Stable across re-renders; changing it is a remove plus an add |
  | `data-hm-spec` | The MapLibre specification, JSON-encoded |
  | `data-hm-events` | Event name to action-dispatch descriptor, JSON-encoded |
  | `data-hm-map` | The cid of the owning map. Debugging aid; the reconciler uses DOM containment |

  You only need this module to write a definition component of your own — see
  `__using__/1`. Using the components in `HoloMap` requires none of it.
  """

  alias HoloMap.Event
  alias HoloMap.JSON

  @context_key {HoloMap.Map, :cid}

  @doc """
  The context key `HoloMap.Map` publishes its cid under.

  Namespaced by module, as Hologram recommends, so it cannot collide with an
  application's own context.
  """
  @spec context_key() :: {module(), atom()}
  def context_key, do: @context_key

  @doc """
  Makes the calling module a map-definition component.

  Injects `use Hologram.Component` and the `map_cid` prop, which is sourced
  from the context `HoloMap.Map` publishes.

  Pair it with `map_cid!/1` in the template. Together they turn "definition
  component rendered outside a map" — otherwise a stray element that silently
  never becomes part of anything — into a named error that says what to do.

      defmodule MyApp.HeatmapLayer do
        use HoloMap.Def

        prop :id, :string, required: true

        def template do
          ~HOLO\"""
          <div data-hm="layer" data-hm-key={@id}
               data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
               data-hm-spec={HoloMap.Def.spec(%{"type" => "heatmap"})}></div>
          \"""
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      use Hologram.Component

      prop :map_cid, :string, from_context: unquote(Macro.escape(@context_key)), default: nil
    end
  end

  @doc """
  Returns the owning map's cid, or raises if there is not one.

  A definition component reads the cid from context, so `nil` means no
  `HoloMap.Map` is above it in the tree. Hologram would otherwise surface that
  as a bare `KeyError` on an internal prop name, which says nothing about what
  the caller did wrong.

      iex> HoloMap.Def.map_cid!("explorer")
      "explorer"
  """
  @spec map_cid!(String.t() | nil) :: String.t()
  def map_cid!(nil) do
    raise ArgumentError,
          "a HoloMap definition component was rendered outside a <HoloMap.Map>. " <>
            "Sources, layers, markers, popups, controls, terrain and sky must be nested " <>
            "inside a <HoloMap.Map cid=\"...\">, which is what publishes the map's cid " <>
            "to them through Hologram's Context."
  end

  def map_cid!(cid) when is_binary(cid), do: cid

  @doc """
  Encodes a specification map for a `data-hm-spec` attribute.

  Drops `nil` entries, so a component can hand over its full key table and let
  unset props fall away. See `HoloMap.Spec` for why an absent key and a `null`
  mean different things to MapLibre.

      iex> HoloMap.Def.spec(%{"type" => "fill", "source" => "parcels", "filter" => nil})
      ~s({"source":"parcels","type":"fill"})
  """
  @spec spec(map()) :: String.t()
  def spec(spec) when is_map(spec) do
    spec
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
    |> JSON.encode()
  end

  @doc """
  Encodes event-handler props for a `data-hm-events` attribute.

  Takes a keyword list of `{maplibre_event_name, handler_prop}`. Unset handlers
  are dropped rather than encoded as `null`, which keeps the attribute stable
  when a component declares more events than the caller uses — a changed
  attribute string is what makes the reconciler rebind listeners.

      iex> HoloMap.Def.events(click: :parcel_clicked, mouseleave: nil)
      ~s({"click":{"action":"parcel_clicked","params":{},"target":"page"}})

      iex> HoloMap.Def.events(click: nil)
      "{}"
  """
  @spec events(keyword()) :: String.t()
  def events(pairs) when is_list(pairs) do
    pairs
    |> Enum.reduce(%{}, fn {name, handler}, acc ->
      case Event.normalize(handler) do
        nil -> acc
        normalized -> Map.put(acc, Atom.to_string(name), normalized)
      end
    end)
    |> JSON.encode()
  end

  @doc """
  Resolves a `visible` prop into a MapLibre `visibility` layout property.

  Visibility is a layout property rather than a top-level layer key, but it is
  common enough to deserve its own prop. `nil` leaves the layout map untouched,
  so a caller setting `visibility` by hand is not overridden.

      iex> HoloMap.Def.visibility(%{"line-cap" => "round"}, false)
      %{"line-cap" => "round", "visibility" => "none"}

      iex> HoloMap.Def.visibility(%{}, nil)
      %{}
  """
  @spec visibility(map(), boolean() | nil) :: map()
  def visibility(layout, nil), do: layout
  def visibility(layout, true), do: Map.put(layout, "visibility", "visible")
  def visibility(layout, false), do: Map.put(layout, "visibility", "none")
end
