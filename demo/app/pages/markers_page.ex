defmodule Demo.MarkersPage do
  use Hologram.Page

  route "/markers"
  layout Demo.MainLayout, page_title: "Markers and popups — HoloMap"

  @style_url "https://demotiles.maplibre.org/style.json"

  def init(_params, component, _server) do
    put_state(component,
      style: @style_url,
      selected: nil,
      pin: [-69.93, 18.48]
    )
  end

  def template do
    ~HOLO"""
    <h1>Markers and popups</h1>
    <p>
      Markers are DOM elements above the map: cheap to style, expensive in bulk. The
      draggable one writes its position back into state on every <code>dragend</code>.
    </p>

    <div class="controls">
      <span>draggable pin: {Demo.MarkersPage.format(@pin)}</span>
      <button $click={:clear}>Clear popup</button>
    </div>

    <HoloMap.Map
      cid="markers"
      style={@style}
      center={{-70.0, 19.0}}
      zoom={6}
      height="480px"
      class="map"
      on_click={:clear}
    >
      <HoloMap.Control.Navigation />

      <HoloMap.Marker
        id="default-pin"
        lng_lat={{-70.70, 19.45}}
        color="#dc2626"
        on_click={%{action: :select, params: %{name: "Santiago"}}}
      />

      <HoloMap.Marker id="custom-pin" lng_lat={{-68.37, 18.58}}
                      on_click={%{action: :select, params: %{name: "Punta Cana"}}}>
        <div class="chip">Punta Cana</div>
      </HoloMap.Marker>

      <HoloMap.Marker
        id="draggable-pin"
        lng_lat={@pin}
        color="#059669"
        draggable
        on_drag_end={:pin_moved}
      />

      {%if @selected}
        <HoloMap.Popup id="details" lng_lat={@selected.coords} close_on_move={false}>
          <h3>{@selected.name}</h3>
          <p>Rendered from page state — closing it means clearing that state.</p>
        </HoloMap.Popup>
      {/if}
    </HoloMap.Map>
    """
  end

  @doc false
  def format([lng, lat]), do: "#{Float.round(lng * 1.0, 4)}, #{Float.round(lat * 1.0, 4)}"

  def action(:select, params, component) do
    coords =
      case params.name do
        "Santiago" -> [-70.70, 19.45]
        _other -> [-68.37, 18.58]
      end

    put_state(component, :selected, %{name: params.name, coords: coords})
  end

  def action(:pin_moved, params, component) do
    put_state(component, :pin, params.lng_lat)
  end

  def action(:clear, _params, component) do
    put_state(component, :selected, nil)
  end
end
