defmodule Demo.TerrainPage do
  use Hologram.Page

  route "/terrain"
  layout Demo.MainLayout, page_title: "Terrain, hillshade and sky — HoloMap"

  # The elevation source MapLibre's own "Sky, Fog, Terrain" example uses.
  # Global coverage, terrarium-encoded.
  @dem "https://tiles.mapterhorn.com/tilejson.json"

  def init(_params, component, _server) do
    put_state(component,
      style: "https://demotiles.maplibre.org/style.json",
      dem: @dem,
      exaggeration: 1.4,
      pitch: 70,
      hillshade: true,
      sky: true
    )
  end

  def template do
    ~HOLO"""
    <h1>Terrain, hillshade and sky</h1>
    <p>
      One <code>HoloMap.Source.RasterDEM</code> feeding two very different things: a
      <code>HoloMap.Terrain</code> that displaces the whole map vertically, and a
      <code>HoloMap.Layer.Hillshade</code> that shades it. <code>HoloMap.Sky</code> puts an
      atmosphere at the horizon.
    </p>
    <p>
      Terrain does nothing at zero pitch — a hill seen from directly above still looks flat —
      and the sky is only drawn where the horizon is on screen. Flatten the view below and both
      disappear, which is correct rather than broken.
    </p>

    <div class="controls">
      <button $click={:set_pitch, value: 0}>Flat</button>
      <button $click={:set_pitch, value: 70}>Tilted</button>
      <button $click={:set_exaggeration, value: 1.0}>True scale</button>
      <button $click={:set_exaggeration, value: 2.5}>Exaggerated</button>
      <button $click={:toggle_hillshade}>{Demo.TerrainPage.toggle_label(@hillshade, "hillshade")}</button>
      <button $click={:toggle_sky}>{Demo.TerrainPage.toggle_label(@sky, "sky")}</button>
      <span>pitch {@pitch} · ×{@exaggeration}</span>
    </div>

    <HoloMap.Map
      cid="relief"
      style={@style}
      center={{11.39, 47.27}}
      zoom={11}
      pitch={@pitch}
      max_pitch={85}
      bearing={-20}
      height="540px"
      class="map"
      attribution_control={false}
    >
      <HoloMap.Source.RasterDEM id="dem" url={@dem} encoding="terrarium" />

      <HoloMap.Terrain source="dem" exaggeration={@exaggeration} />

      {%if @hillshade}
        <HoloMap.Layer.Hillshade
          id="relief-shade"
          source="dem"
          paint={%{
            hillshade_exaggeration: 0.5,
            hillshade_illumination_direction: 315,
            hillshade_shadow_color: "#000000",
            hillshade_highlight_color: "#ffffff",
            hillshade_accent_color: "#000000"
          }}
        />
      {/if}

      {%if @sky}
        <HoloMap.Sky
          sky_color="#199EF3"
          sky_horizon_blend={0.5}
          horizon_color="#ffffff"
          horizon_fog_blend={0.5}
          fog_color="#0f172a"
          fog_ground_blend={0.1}
        />
      {/if}

      <HoloMap.Control.Navigation position="top-right" visualize_pitch />
      <HoloMap.Control.Attribution position="bottom-right" compact />
    </HoloMap.Map>
    """
  end

  @doc false
  def toggle_label(true, what), do: "Hide #{what}"
  def toggle_label(false, what), do: "Show #{what}"

  def action(:set_pitch, params, component), do: put_state(component, :pitch, params.value)

  def action(:set_exaggeration, params, component) do
    put_state(component, :exaggeration, params.value)
  end

  def action(:toggle_hillshade, _params, component) do
    put_state(component, :hillshade, !component.state.hillshade)
  end

  def action(:toggle_sky, _params, component) do
    put_state(component, :sky, !component.state.sky)
  end
end
