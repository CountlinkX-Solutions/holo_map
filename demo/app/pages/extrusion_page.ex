defmodule Demo.ExtrusionPage do
  use Hologram.Page

  route "/extrusion"
  layout Demo.MainLayout, page_title: "3D extrusion — HoloMap"

  # The basemap MapLibre's own "Display buildings in 3D" example uses: a free,
  # keyless vector style whose `openmaptiles` source carries a `building` layer
  # with per-building heights from OpenStreetMap.
  @basemap "https://tiles.openfreemap.org/styles/bright"

  # 3D buildings belong above the roads and below the labels. This is the first
  # label layer in that style, so inserting before it puts them in the right
  # place without hiding street names.
  @before_labels "waterway_line_label"

  @osm_tiles ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"]

  def init(_params, component, _server) do
    put_state(component,
      basemap: @basemap,
      before_labels: @before_labels,
      osm_tiles: @osm_tiles,
      street_style: street_style(),
      blocks: blocks(),
      scale: 1,
      base_visible: true
    )
  end

  def template do
    ~HOLO"""
    <h1>3D extrusion</h1>
    <p>
      <code>HoloMap.Layer.FillExtrusion</code> raises polygons by a data-driven height. There
      are two ways to feed it, and both are here — the second map is a separate
      <code>HoloMap.Map</code> on the same page, which is all it takes to run two.
    </p>

    <h2>Buildings from the basemap</h2>
    <p>
      The layer below reads from a source this library did not declare: the
      <code>openmaptiles</code> source that comes with the style itself. A layer can name any
      source the style provides, which is how you add to a basemap rather than replace it.
      <code>before_id</code> slots the buildings above the roads and beneath the labels.
    </p>

    <HoloMap.Map
      cid="buildings"
      style={@basemap}
      center={{-74.0066, 40.7135}}
      zoom={15.5}
      pitch={45}
      bearing={-17.6}
      max_pitch={85}
      height="520px"
      class="map"
    >
      <HoloMap.Layer.FillExtrusion
        id="osm-buildings"
        source="openmaptiles"
        source_layer="building"
        min_zoom={15}
        before_id={@before_labels}
        filter={["!=", ["get", "hide_3d"], true]}
        paint={%{
          fill_extrusion_color: [
            "interpolate",
            ["linear"],
            ["get", "render_height"],
            0,
            "lightgray",
            200,
            "royalblue",
            400,
            "lightblue"
          ],
          fill_extrusion_height: [
            "interpolate",
            ["linear"],
            ["zoom"],
            15,
            0,
            16,
            ["get", "render_height"]
          ],
          fill_extrusion_base: [
            "case",
            [">=", ["get", "zoom"], 16],
            ["get", "render_min_height"],
            0
          ],
          fill_extrusion_opacity: 0.9
        }}
      />

      <HoloMap.Control.Navigation position="top-right" visualize_pitch />
    </HoloMap.Map>

    <h2>Geometry your application owns</h2>
    <p>
      Here the polygons are built in Elixir and handed over as a
      <code>HoloMap.Source.GeoJSON</code> — the usual case for indoor plans, zoning envelopes or
      planned volumes, where the heights are whatever your application decides they are.
      Changing the multiplier rewrites the <code>fill-extrusion-height</code> expression and
      reaches MapLibre as <code>setPaintProperty</code>; nothing is rebuilt.
    </p>

    <div class="controls">
      <button $click={:set_scale, value: 1}>×1</button>
      <button $click={:set_scale, value: 3}>×3</button>
      <button $click={:set_scale, value: 6}>×6</button>
      <button $click={:toggle_base}>{Demo.ExtrusionPage.base_label(@base_visible)}</button>
      <span>height ×{@scale}</span>
    </div>

    <HoloMap.Map
      cid="blocks"
      style={@street_style}
      center={{-69.9312, 18.4718}}
      zoom={16}
      pitch={60}
      bearing={-25}
      max_pitch={85}
      height="520px"
      class="map"
      attribution_control={false}
    >
      <HoloMap.Source.Raster
        id="osm"
        tiles={@osm_tiles}
        tile_size={256}
        max_zoom={19}
        attribution="© OpenStreetMap contributors"
      />
      <HoloMap.Layer.Raster id="osm-base" source="osm" paint={%{raster_opacity: 0.75}} />

      <HoloMap.Source.GeoJSON id="blocks" data={@blocks} />

      <HoloMap.Layer.Fill
        id="blocks-footprint"
        source="blocks"
        visible={@base_visible}
        paint={%{fill_color: "#1e293b", fill_opacity: 0.35}}
      />

      <HoloMap.Layer.FillExtrusion
        id="blocks-3d"
        source="blocks"
        paint={%{
          fill_extrusion_color: [
            "interpolate",
            ["linear"],
            ["get", "height"],
            10,
            "#38bdf8",
            60,
            "#f472b6"
          ],
          fill_extrusion_height: ["*", ["get", "height"], @scale],
          fill_extrusion_base: ["get", "base"],
          fill_extrusion_opacity: 0.85,
          fill_extrusion_vertical_gradient: true
        }}
      />

      <HoloMap.Control.Navigation position="top-right" visualize_pitch />
      <HoloMap.Control.Attribution position="bottom-right" compact />
    </HoloMap.Map>
    """
  end

  @doc false
  def base_label(true), do: "Hide footprints"
  def base_label(false), do: "Show footprints"

  def action(:set_scale, params, component), do: put_state(component, :scale, params.value)

  def action(:toggle_base, _params, component) do
    put_state(component, :base_visible, !component.state.base_visible)
  end

  # A deterministic grid of blocks. Deterministic because this runs on the
  # client too, where :rand would redraw the city on every re-render.
  defp blocks do
    features =
      for row <- 0..5, col <- 0..5 do
        lng = -69.9360 + col * 0.0018
        lat = 18.4690 + row * 0.0014
        height = 12 + rem(row * 7 + col * 13, 9) * 6

        %{
          "type" => "Feature",
          "properties" => %{"height" => height, "base" => 0},
          "geometry" => %{
            "type" => "Polygon",
            "coordinates" => [
              [
                [lng, lat],
                [lng + 0.0011, lat],
                [lng + 0.0011, lat + 0.0009],
                [lng, lat + 0.0009],
                [lng, lat]
              ]
            ]
          }
        }
      end

    %{"type" => "FeatureCollection", "features" => features}
  end

  # A style whose only job is to hold a background; the streets underneath come
  # from the raster source declared in the template, like MapLibre's own indoor
  # mapping example.
  defp street_style do
    %{
      "version" => 8,
      "sources" => %{},
      "layers" => [
        %{
          "id" => "background",
          "type" => "background",
          "paint" => %{"background-color" => "#f8fafc"}
        }
      ]
    }
  end
end
