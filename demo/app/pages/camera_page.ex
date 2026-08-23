defmodule Demo.CameraPage do
  use Hologram.Page

  route "/camera"
  layout Demo.MainLayout, page_title: "Camera API - HoloMap", active: :camera

  @style_url "https://demotiles.maplibre.org/style.json"

  @places [
    %{name: "Santo Domingo", lng: -69.93, lat: 18.48, zoom: 11},
    %{name: "Reykjavík", lng: -21.94, lat: 64.15, zoom: 10},
    %{name: "Kyoto", lng: 135.77, lat: 35.01, zoom: 11},
    %{name: "Cape Town", lng: 18.42, lat: -33.93, zoom: 10}
  ]

  def init(_params, component, _server) do
    put_state(component,
      style: @style_url,
      places: @places,
      last: nil,
      narrow: false
    )
  end

  def template do
    ~HOLO"""
    <h1>Camera API</h1>
    <p>
      Flying somewhere is an event, not a value. Re-rendering the same centre twice
      should not re-animate. That is what <code>HoloMap.API</code> is for, and it is
      called from an ordinary action.
    </p>

    <div class="controls">
      {%for place <- @places}
        <button $click={:go, name: place.name, lng: place.lng, lat: place.lat, zoom: place.zoom}>
          {place.name}
        </button>
      {/for}
      <button $click={:whole_world}>Fit world</button>
      <button $click={:jump}>Jump to origin</button>
      <span>{@last}</span>
    </div>

    <div class="controls">
      <button $click={:tilt}>Tilt and rotate</button>
      <button $click={:ease}>Ease north-up</button>
      <span>bearing and pitch</span>
    </div>

    <HoloMap.Map cid="camera" style={@style} center={{0.0, 20.0}} zoom={2}
                 height="480px" class="map">
      <HoloMap.Control.Navigation visualize_pitch />
    </HoloMap.Map>

    <h2>When resize actually matters</h2>
    <p>
      MapLibre watches its own container, so a map that changes size follows along by itself and
      <code>HoloMap.API.resize/1</code> has nothing to do. The one case where it does is a map
      built with <code>track_resize={false}</code>, which switches that observer off.
    </p>
    <p>
      The map below is one of those. Narrow its container and the canvas keeps its old width until
      you ask for a resize.
    </p>

    <div class="controls">
      <button $click={:toggle_width}>{Demo.CameraPage.width_label(@narrow)}</button>
      <button $click={:resize}>Resize</button>
      <span>{Demo.CameraPage.width_of(@narrow)}</span>
    </div>

    <HoloMap.Map
      cid="stale"
      style={@style}
      center={{2.35, 48.86}}
      zoom={4}
      height="320px"
      class={"map " <> Demo.CameraPage.width_class(@narrow)}
      track_resize={false}
    >
      <HoloMap.Control.Navigation />
    </HoloMap.Map>
    """
  end

  def action(:go, params, component) do
    HoloMap.API.fly_to("camera",
      center: {params.lng, params.lat},
      zoom: params.zoom,
      duration: 2_000
    )

    put_state(component, :last, "flew to #{params.name}")
  end

  def action(:tilt, _params, component) do
    HoloMap.API.ease_to("camera", bearing: 45, pitch: 60, duration: 900)
    put_state(component, :last, "tilted and rotated")
  end

  def action(:ease, _params, component) do
    HoloMap.API.ease_to("camera", bearing: 0, pitch: 0, duration: 900)
    put_state(component, :last, "eased back to north-up")
  end

  def action(:jump, _params, component) do
    HoloMap.API.jump_to("camera", center: {0.0, 0.0}, zoom: 2)
    put_state(component, :last, "jumped to 0, 0")
  end

  def action(:toggle_width, _params, component) do
    put_state(component, :narrow, !component.state.narrow)
  end

  def action(:resize, _params, component) do
    HoloMap.API.resize("stale")
    component
  end

  def action(:whole_world, _params, component) do
    HoloMap.API.fit_bounds("camera", [-170.0, -60.0, 170.0, 75.0], padding: 40, duration: 1_500)

    put_state(component, :last, "fitted the world")
  end

  @doc false
  def width_label(true), do: "Widen the container"
  def width_label(false), do: "Narrow the container"

  @doc false
  def width_of(true), do: "420px"
  def width_of(false), do: "100%"

  @doc false
  def width_class(true), do: "w-[420px]"
  def width_class(false), do: "w-full"
end
