defmodule Demo.BasicPage do
  use Hologram.Page

  route "/basic"
  layout Demo.MainLayout, page_title: "Basic map - HoloMap", active: :basic

  # In a HOLO template `@style` resolves to a prop or state entry, never to a
  # module attribute, so the style URL goes into state like any other value.
  @style_url "https://demotiles.maplibre.org/style.json"

  def init(_params, component, _server) do
    put_state(component, style: @style_url, zoom: 3, pitch: 0, log: [])
  end

  def template do
    ~HOLO"""
    <h1>Basic map</h1>
    <p>
      The camera below is component state. The buttons write to that state, and the map
      follows. There is no imperative call anywhere on this page.
    </p>

    <div class="controls">
      <button $click={:zoom_in}>Zoom in</button>
      <button $click={:zoom_out}>Zoom out</button>
      <button $click={:tilt}>Toggle tilt</button>
      <span>zoom {@zoom} · pitch {@pitch}</span>
    </div>

    <HoloMap.Map
      cid="basic"
      style={@style}
      center={{0.0, 20.0}}
      zoom={@zoom}
      pitch={@pitch}
      height="480px"
      class="map"
      on_move_end={:camera_moved}
    >
      <HoloMap.Control.Navigation position="top-right" visualize_pitch />
      <HoloMap.Control.Scale position="bottom-left" unit="metric" />
      <HoloMap.Control.Fullscreen position="top-left" />
    </HoloMap.Map>

    <h2>Camera events</h2>
    <ul class="log">
      {%for entry <- @log}
        <li>{entry}</li>
      {/for}
    </ul>
    """
  end

  def action(:zoom_in, _params, component) do
    put_state(component, :zoom, min(component.state.zoom + 1, 18))
  end

  def action(:zoom_out, _params, component) do
    put_state(component, :zoom, max(component.state.zoom - 1, 0))
  end

  def action(:tilt, _params, component) do
    put_state(component, :pitch, if(component.state.pitch == 0, do: 60, else: 0))
  end

  def action(:camera_moved, params, component) do
    [lng, lat] = params.center
    # MapLibre reports a whole-number coordinate as an integer, and Float.round/2
    # only accepts floats, so the payload is widened before rounding.
    entry =
      "moveend · #{Float.round(lng * 1.0, 3)}, #{Float.round(lat * 1.0, 3)}" <>
        " @ z#{Float.round(params.zoom * 1.0, 2)}"

    put_state(component, :log, Enum.take([entry | component.state.log], 8))
  end
end
