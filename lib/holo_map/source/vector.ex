defmodule HoloMap.Source.Vector do
  @moduledoc """
  Vector tiles, from a TileJSON endpoint or an explicit tile URL template.

      <HoloMap.Source.Vector id="basemap" url="https://tiles.example.com/basemap.json" />

      <HoloMap.Source.Vector
        id="parcels"
        tiles={["https://tiles.example.com/parcels/{z}/{x}/{y}.pbf"]}
        min_zoom={8}
        max_zoom={14}
      />

  Layers reading from a vector source **must** set `source_layer` — a vector
  tile carries several named layers and MapLibre has no way to guess which one
  is meant:

      <HoloMap.Layer.Fill id="water" source="basemap" source_layer="water"
                          paint={%{fill_color: "#a5d8ff"}} />

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** Referenced by layers' `source` prop |
  | `url` | string | TileJSON endpoint. Supply this or `tiles` |
  | `tiles` | list | Tile URL templates containing `{z}`, `{x}`, `{y}` |
  | `min_zoom` / `max_zoom` | number | Zoom range the tiles exist at |
  | `bounds` | list | `[west, south, east, north]` extent of the data |
  | `scheme` | string | `"xyz"` (default) or `"tms"` |
  | `promote_id` | string or map | Property to use as the feature id |
  | `volatile` | boolean | Skip the tile cache |
  | `attribution` | string | Attribution text |

  Changing any of these is a structural update: the source is torn down and
  rebuilt, and the layers on top of it are detached and re-added around that.
  """

  use HoloMap.Def

  @keys [
    url: "url",
    tiles: "tiles",
    bounds: "bounds",
    scheme: "scheme",
    min_zoom: "minzoom",
    max_zoom: "maxzoom",
    attribution: "attribution",
    promote_id: "promoteId",
    volatile: "volatile"
  ]

  prop :id, :string, required: true
  prop :url, :string, default: nil
  prop :tiles, :list, default: nil
  prop :bounds, :list, default: nil
  prop :scheme, :string, default: nil
  prop :min_zoom, :any, default: nil
  prop :max_zoom, :any, default: nil
  prop :attribution, :string, default: nil
  prop :promote_id, :any, default: nil
  prop :volatile, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="source"
      data-hm-key={@id}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Source.build(%{
        url: @url,
        tiles: @tiles,
        bounds: @bounds,
        scheme: @scheme,
        min_zoom: @min_zoom,
        max_zoom: @max_zoom,
        attribution: @attribution,
        promote_id: @promote_id,
        volatile: @volatile
      }, HoloMap.Source.Vector.__keys__(), "vector", [:volatile])}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
