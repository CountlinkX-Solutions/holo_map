defmodule Demo.ExtrusionPage do
  use Hologram.Page

  route "/extrusion"
  layout Demo.MainLayout, page_title: "3D extrusion — HoloMap"

  def init(_params, component, _server) do
    put_state(component,
      style: base_style(),
      blocks: blocks(),
      scale: 1,
      base_visible: true
    )
  end

  def template do
    ~HOLO"""
    <h1>3D extrusion</h1>
    <p>
      <code>HoloMap.Layer.FillExtrusion</code> raises polygons by a data-driven height. The
      geometry here is built in Elixir — no external source is involved — so the heights are
      whatever your application decides they are, which is the usual case for indoor plans,
      zoning envelopes or planned volumes.
    </p>
    <p>
      Changing the multiplier below rewrites the <code>fill-extrusion-height</code> expression
      and reaches MapLibre as <code>setPaintProperty</code>. The buildings grow; nothing is
      rebuilt.
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
      style={@style}
      center={{-69.9312, 18.4718}}
      zoom={16}
      pitch={60}
      bearing={-25}
      max_pitch={85}
      height="540px"
      class="map"
      attribution_control={false}
    >
      <HoloMap.Source.GeoJSON id="blocks" data={@blocks} />

      <HoloMap.Layer.Fill
        id="blocks-footprint"
        source="blocks"
        visible={@base_visible}
        paint={%{fill_color: "#1e293b", fill_opacity: 0.6}}
      />

      <HoloMap.Layer.FillExtrusion
        id="blocks-3d"
        source="blocks"
        paint={%{
          fill_extrusion_color: ["interpolate", ["linear"], ["get", "height"], 10, "#38bdf8", 60, "#f472b6"],
          fill_extrusion_height: ["*", ["get", "height"], @scale],
          fill_extrusion_base: ["get", "base"],
          fill_extrusion_opacity: 0.9,
          fill_extrusion_vertical_gradient: true
        }}
      />

      <HoloMap.Control.Navigation position="top-right" visualize_pitch />
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

  defp base_style do
    %{
      "version" => 8,
      "sources" => %{},
      "layers" => [
        %{
          "id" => "background",
          "type" => "background",
          "paint" => %{"background-color" => "#0b1120"}
        }
      ]
    }
  end
end
