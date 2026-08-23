defmodule HoloMap.Source.Raster do
  @moduledoc """
  Raster tiles: aerial imagery, scanned maps, any pre-rendered tile pyramid.

      <HoloMap.Source.Raster
        id="ortho"
        tiles={["https://tiles.example.com/ortho/{z}/{x}/{y}.png"]}
        tile_size={256}
        attribution="© Example Imagery"
      />
      <HoloMap.Layer.Raster id="ortho-layer" source="ortho" paint={%{raster_opacity: 0.8}} />

  `tile_size` matters more than it looks: `256` is the classic scheme, `512`
  matches the vector-tile grid. Getting it wrong does not error. It shifts the
  imagery half a zoom level out of alignment with everything else.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** Referenced by layers' `source` prop |
  | `url` | string | TileJSON endpoint. Supply this or `tiles` |
  | `tiles` | list | Tile URL templates containing `{z}`, `{x}`, `{y}` |
  | `tile_size` | number | Pixel size of one tile, usually 256 or 512 |
  | `min_zoom` / `max_zoom` | number | Zoom range the tiles exist at |
  | `bounds` | list | `[west, south, east, north]` extent of the imagery |
  | `scheme` | string | `"xyz"` (default) or `"tms"` |
  | `volatile` | boolean | Skip the tile cache |
  | `attribution` | string | Attribution text |
  """

  use HoloMap.Def

  @keys [
    url: "url",
    tiles: "tiles",
    bounds: "bounds",
    scheme: "scheme",
    min_zoom: "minzoom",
    max_zoom: "maxzoom",
    tile_size: "tileSize",
    attribution: "attribution",
    volatile: "volatile"
  ]

  prop :id, :string, required: true
  prop :url, :string, default: nil
  prop :tiles, :list, default: nil
  prop :bounds, :list, default: nil
  prop :scheme, :string, default: nil
  prop :min_zoom, :any, default: nil
  prop :max_zoom, :any, default: nil
  prop :tile_size, :any, default: nil
  prop :attribution, :string, default: nil
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
        tile_size: @tile_size,
        attribution: @attribution,
        volatile: @volatile
      }, HoloMap.Source.Raster.__keys__(), "raster", [:volatile])}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
