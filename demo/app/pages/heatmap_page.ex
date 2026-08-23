defmodule Demo.HeatmapPage do
  use Hologram.Page

  route "/heatmap"
  layout Demo.MainLayout, page_title: "Heatmap - HoloMap", active: :heatmap

  # The earthquake feed MapLibre's own heatmap example uses: 6,107 points.
  @earthquakes "https://maplibre.org/maplibre-gl-js/docs/assets/earthquakes.geojson"

  def init(_params, component, _server) do
    put_state(component,
      style: "https://demotiles.maplibre.org/style.json",
      data: @earthquakes,
      intensity: 1
    )
  end

  def template do
    ~HOLO"""
    <h1>Heatmap</h1>
    <p>
      Six thousand earthquakes, fetched by URL rather than inlined. A
      <code>HoloMap.Source.GeoJSON</code>'s <code>data</code> prop takes either. The heatmap
      fades out as you zoom in and individual circles fade in, which is two layers with
      opposing zoom-driven opacity rather than any switching logic.
    </p>

    <div class="controls">
      <button $click={:set_intensity, value: 1}>Normal</button>
      <button $click={:set_intensity, value: 3}>Intense</button>
      <span>intensity ×{@intensity}</span>
    </div>

    <HoloMap.Map
      cid="quakes"
      style={@style}
      center={{-100.0, 38.0}}
      zoom={3}
      height="520px"
      class="map"
    >
      <HoloMap.Source.GeoJSON id="earthquakes" data={@data} />

      <HoloMap.Layer.Heatmap
        id="earthquakes-heat"
        source="earthquakes"
        max_zoom={9}
        paint={%{
          heatmap_weight: ["interpolate", ["linear"], ["get", "mag"], 0, 0, 6, 1],
          heatmap_intensity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            0,
            @intensity,
            9,
            @intensity * 3
          ],
          heatmap_color: [
            "interpolate",
            ["linear"],
            ["heatmap-density"],
            0,
            "rgba(33,102,172,0)",
            0.2,
            "rgb(103,169,207)",
            0.4,
            "rgb(209,229,240)",
            0.6,
            "rgb(253,219,199)",
            0.8,
            "rgb(239,138,98)",
            1,
            "rgb(178,24,43)"
          ],
          heatmap_radius: ["interpolate", ["linear"], ["zoom"], 0, 2, 9, 20],
          heatmap_opacity: ["interpolate", ["linear"], ["zoom"], 7, 1, 9, 0]
        }}
      />

      <HoloMap.Layer.Circle
        id="earthquakes-points"
        source="earthquakes"
        min_zoom={7}
        paint={%{
          circle_radius: [
            "interpolate",
            ["linear"],
            ["zoom"],
            7,
            ["interpolate", ["linear"], ["get", "mag"], 1, 1, 6, 4],
            16,
            ["interpolate", ["linear"], ["get", "mag"], 1, 5, 6, 50]
          ],
          circle_color: [
            "interpolate",
            ["linear"],
            ["get", "mag"],
            1,
            "rgba(33,102,172,0)",
            2,
            "rgb(103,169,207)",
            3,
            "rgb(209,229,240)",
            4,
            "rgb(253,219,199)",
            5,
            "rgb(239,138,98)",
            6,
            "rgb(178,24,43)"
          ],
          circle_stroke_color: "white",
          circle_stroke_width: 1,
          circle_opacity: ["interpolate", ["linear"], ["zoom"], 7, 0, 8, 1]
        }}
      />

      <HoloMap.Control.Navigation position="top-right" />
      <HoloMap.Control.Geolocate
        position="top-right"
        track_user_location
        show_user_heading
        position_options={%{"enableHighAccuracy" => true}}
      />
    </HoloMap.Map>
    """
  end

  def action(:set_intensity, params, component) do
    put_state(component, :intensity, params.value)
  end
end
