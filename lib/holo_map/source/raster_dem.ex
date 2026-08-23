defmodule HoloMap.Source.RasterDEM do
  @moduledoc """
  Elevation tiles, encoded as RGB. The input for terrain and hillshade.

      <HoloMap.Source.RasterDEM
        id="dem"
        tiles={["https://tiles.example.com/dem/{z}/{x}/{y}.png"]}
        encoding="terrarium"
        tile_size={256}
      />

      <HoloMap.Terrain source="dem" exaggeration={1.5} />
      <HoloMap.Layer.Hillshade id="relief" source="dem" />

  ## Encoding

  `encoding` must match how the tiles were produced, and there is no way to
  detect it — the wrong value renders a plausible-looking but entirely fictional
  landscape.

    * `"mapbox"` — the Mapbox Terrain-RGB scheme (the default)
    * `"terrarium"` — the Mapzen/AWS Terrain Tiles scheme
    * `"custom"` — supply your own `red_factor`, `green_factor`, `blue_factor`
      and `base_shift`

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** Referenced by `HoloMap.Terrain` and hillshade layers |
  | `url` | string | TileJSON endpoint. Supply this or `tiles` |
  | `tiles` | list | Tile URL templates containing `{z}`, `{x}`, `{y}` |
  | `encoding` | string | `"mapbox"`, `"terrarium"` or `"custom"` |
  | `tile_size` | number | Pixel size of one tile |
  | `min_zoom` / `max_zoom` | number | Zoom range the tiles exist at |
  | `bounds` | list | `[west, south, east, north]` extent of the data |
  | `red_factor` / `green_factor` / `blue_factor` / `base_shift` | number | Custom encoding coefficients |
  | `attribution` | string | Attribution text |
  """

  use HoloMap.Def

  @keys [
    url: "url",
    tiles: "tiles",
    bounds: "bounds",
    min_zoom: "minzoom",
    max_zoom: "maxzoom",
    tile_size: "tileSize",
    encoding: "encoding",
    red_factor: "redFactor",
    green_factor: "greenFactor",
    blue_factor: "blueFactor",
    base_shift: "baseShift",
    attribution: "attribution"
  ]

  prop :id, :string, required: true
  prop :url, :string, default: nil
  prop :tiles, :list, default: nil
  prop :bounds, :list, default: nil
  prop :min_zoom, :any, default: nil
  prop :max_zoom, :any, default: nil
  prop :tile_size, :any, default: nil
  prop :encoding, :string, default: nil
  prop :red_factor, :any, default: nil
  prop :green_factor, :any, default: nil
  prop :blue_factor, :any, default: nil
  prop :base_shift, :any, default: nil
  prop :attribution, :string, default: nil

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
        min_zoom: @min_zoom,
        max_zoom: @max_zoom,
        tile_size: @tile_size,
        encoding: @encoding,
        red_factor: @red_factor,
        green_factor: @green_factor,
        blue_factor: @blue_factor,
        base_shift: @base_shift,
        attribution: @attribution
      }, HoloMap.Source.RasterDEM.__keys__(), "raster-dem")}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
