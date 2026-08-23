defmodule Demo.MarkersPage do
  use Hologram.Page

  route "/markers"
  layout Demo.MainLayout, page_title: "Markers and popups — HoloMap"

  @style_url "https://demotiles.maplibre.org/style.json"

  # From MapLibre's own documentation assets. Note that the demo-tiles style
  # ships no sprite at all, so without HoloMap.Image there is no icon name a
  # symbol layer could possibly resolve.
  @icon "https://maplibre.org/maplibre-gl-js/docs/assets/custom_marker.png"

  def init(_params, component, _server) do
    put_state(component,
      style: @style_url,
      selected: nil,
      pin: [-69.93, 18.48],
      drag_events: 0,
      drag_phase: "idle",
      icon: @icon,
      places: places(),
      icon_size: 0.5
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
      <span>draggable pin: {Demo.MarkersPage.format(@pin)} · {@drag_phase} · {@drag_events} drag events</span>
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
        on_drag_start={:pin_drag_started}
        on_drag={:pin_dragging}
        on_drag_end={:pin_moved}
      />

      {%if @selected}
        <HoloMap.Popup id="details" lng_lat={@selected.coords} close_on_move={false}>
          <h3>{@selected.name}</h3>
          <p>Rendered from page state — closing it means clearing that state.</p>
        </HoloMap.Popup>
      {/if}
    </HoloMap.Map>

    <h2>The same idea at scale</h2>
    <p>
      A marker is a DOM node, which is why the map above holds three and not three thousand.
      Past a few dozen, the points belong in a source and a symbol layer, which renders on the
      GPU.
    </p>
    <p>
      That needs an icon, and <code>icon_image</code> names an image rather than fetching one —
      the name has to exist in the style's sprite or be registered first. This style ships no
      sprite at all, so <code>HoloMap.Image</code> is the only thing making the icon below
      resolvable. Remove it and the layer draws nothing, silently.
    </p>

    <div class="controls">
      <button $click={:set_icon_size, value: 0.35}>Small icons</button>
      <button $click={:set_icon_size, value: 0.5}>Medium icons</button>
      <button $click={:set_icon_size, value: 0.9}>Large icons</button>
      <span>icon size {@icon_size}</span>
    </div>

    <HoloMap.Map
      cid="symbols"
      style={@style}
      center={{-70.0, 19.0}}
      zoom={6}
      height="420px"
      class="map"
    >
      <HoloMap.Image id="place-pin" url={@icon} />

      <HoloMap.Source.GeoJSON id="places" data={@places} />

      <HoloMap.Layer.Symbol
        id="places-icons"
        source="places"
        layout={%{
          icon_image: "place-pin",
          icon_size: @icon_size,
          icon_allow_overlap: true,
          icon_anchor: "bottom",
          text_field: ["get", "name"],
          text_size: 11,
          text_offset: [0, 0.6],
          text_anchor: "top"
        }}
        paint={%{text_color: "#111827", text_halo_color: "#ffffff", text_halo_width: 1.5}}
      />

      <HoloMap.Control.Navigation position="top-right" />
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

  def action(:pin_drag_started, _params, component) do
    put_state(component, drag_phase: "dragging", drag_events: 0)
  end

  # Writing the position back on every frame is the demanding case: each one is
  # a state update, a re-render, and a setLngLat back into the marker MapLibre
  # is currently dragging.
  def action(:pin_dragging, params, component) do
    put_state(component,
      pin: params.lng_lat,
      drag_events: component.state.drag_events + 1
    )
  end

  def action(:pin_moved, params, component) do
    put_state(component, pin: params.lng_lat, drag_phase: "idle")
  end

  def action(:clear, _params, component) do
    put_state(component, :selected, nil)
  end

  def action(:set_icon_size, params, component) do
    put_state(component, :icon_size, params.value)
  end

  defp places do
    features =
      for {name, lng, lat} <- [
            {"Santo Domingo", -69.93, 18.48},
            {"Santiago", -70.70, 19.45},
            {"Punta Cana", -68.37, 18.58},
            {"Puerto Plata", -70.69, 19.79},
            {"Barahona", -71.10, 18.21},
            {"Samaná", -69.33, 19.21},
            {"San Juan", -66.11, 18.47}
          ] do
        %{
          "type" => "Feature",
          "properties" => %{"name" => name},
          "geometry" => %{"type" => "Point", "coordinates" => [lng, lat]}
        }
      end

    %{"type" => "FeatureCollection", "features" => features}
  end
end
