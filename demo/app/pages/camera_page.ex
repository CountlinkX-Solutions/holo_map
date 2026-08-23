defmodule Demo.CameraPage do
  use Hologram.Page

  route "/camera"
  layout Demo.MainLayout, page_title: "Camera API — HoloMap"

  @style_url "https://demotiles.maplibre.org/style.json"

  @places [
    %{name: "Santo Domingo", lng: -69.93, lat: 18.48, zoom: 11},
    %{name: "Reykjavík", lng: -21.94, lat: 64.15, zoom: 10},
    %{name: "Kyoto", lng: 135.77, lat: 35.01, zoom: 11},
    %{name: "Cape Town", lng: 18.42, lat: -33.93, zoom: 10}
  ]

  def init(_params, component, _server) do
    put_state(component, style: @style_url, places: @places, last: nil)
  end

  def template do
    ~HOLO"""
    <h1>Camera API</h1>
    <p>
      Flying somewhere is an event, not a value — re-rendering the same centre twice
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
      <span>{@last}</span>
    </div>

    <HoloMap.Map cid="camera" style={@style} center={{0.0, 20.0}} zoom={2}
                 height="480px" class="map">
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

  def action(:whole_world, _params, component) do
    HoloMap.API.fit_bounds("camera", [-170.0, -60.0, 170.0, 75.0], padding: 40, duration: 1_500)

    put_state(component, :last, "fitted the world")
  end
end
