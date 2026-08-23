defmodule Demo.RasterPage do
  use Hologram.Page

  route "/raster"
  layout Demo.MainLayout, page_title: "Raster and image sources — HoloMap"

  # Both taken from MapLibre's own examples: OpenStreetMap's tile server, and
  # the radar frames used by "Animate a series of images".
  @osm_tiles ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"]
  # A literal count, not `Enum.count(0..4)`: Hologram ships a protocol
  # implementation to the browser only for types its compiler can see, and
  # Enumerable.Range is not among them — the range works on the server and
  # raises UndefinedFunctionError on the client.
  @radar_frame_count 5
  @radar_corners [
    {-80.425, 46.437},
    {-71.516, 46.437},
    {-71.516, 37.936},
    {-80.425, 37.936}
  ]

  def init(_params, component, _server) do
    put_state(component,
      style: base_style(),
      osm_tiles: @osm_tiles,
      corners: @radar_corners,
      frame: 0,
      radar_visible: true,
      radar_opacity: 0.85
    )
  end

  def template do
    ~HOLO"""
    <h1>Raster and image sources</h1>
    <p>
      A <code>HoloMap.Source.Raster</code> serving OpenStreetMap tiles, with a
      <code>HoloMap.Source.Image</code> pinned over the north-eastern United States on top.
      Stepping through the radar frames changes the image source's <code>url</code>, which
      MapLibre applies with <code>updateImage</code> — no source is rebuilt and the layer above
      it is never disturbed.
    </p>

    <div class="controls">
      <button $click={:step_frame}>Next radar frame</button>
      <button $click={:toggle_radar}>{Demo.RasterPage.visibility_label(@radar_visible)}</button>
      <button $click={:set_opacity, opacity: 0.35}>Faint</button>
      <button $click={:set_opacity, opacity: 0.85}>Strong</button>
      <span>frame {@frame} · opacity {@radar_opacity}</span>
    </div>

    <HoloMap.Map
      cid="raster"
      style={@style}
      center={{-75.789, 41.874}}
      zoom={5}
      height="480px"
      class="map"
      attribution_control={false}
    >
      <HoloMap.Source.Raster
        id="osm"
        tiles={@osm_tiles}
        tile_size={256}
        min_zoom={0}
        max_zoom={19}
        attribution="© OpenStreetMap contributors"
      />
      <HoloMap.Layer.Raster id="osm-layer" source="osm" />

      <HoloMap.Source.Image
        id="radar"
        url={Demo.RasterPage.frame_url(@frame)}
        coordinates={@corners}
      />
      <HoloMap.Layer.Raster
        id="radar-layer"
        source="radar"
        visible={@radar_visible}
        paint={%{raster_opacity: @radar_opacity, raster_fade_duration: 0}}
      />

      <HoloMap.Control.Navigation position="top-right" />
      <HoloMap.Control.Scale position="bottom-left" />
      <HoloMap.Control.Attribution position="bottom-right" compact />
    </HoloMap.Map>
    """
  end

  @doc false
  def frame_url(frame), do: "https://maplibre.org/maplibre-gl-js/docs/assets/radar#{frame}.gif"

  @doc false
  def visibility_label(true), do: "Hide radar"
  def visibility_label(false), do: "Show radar"

  def action(:step_frame, _params, component) do
    put_state(component, :frame, rem(component.state.frame + 1, @radar_frame_count))
  end

  def action(:toggle_radar, _params, component) do
    put_state(component, :radar_visible, !component.state.radar_visible)
  end

  def action(:set_opacity, params, component) do
    put_state(component, :radar_opacity, params.opacity)
  end

  defp base_style do
    %{
      "version" => 8,
      "sources" => %{},
      "layers" => [
        %{
          "id" => "background",
          "type" => "background",
          "paint" => %{"background-color" => "#e5e7eb"}
        }
      ]
    }
  end
end
