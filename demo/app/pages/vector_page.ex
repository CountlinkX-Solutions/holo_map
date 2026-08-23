defmodule Demo.VectorPage do
  use Hologram.Page

  route "/vector"
  layout Demo.MainLayout, page_title: "Vector tiles - HoloMap", active: :vector

  # MapLibre's own demo tileset. Its vector tiles carry three source layers:
  # countries, centroids and geolines.
  @tiles "https://demotiles.maplibre.org/tiles/tiles.json"

  def init(_params, component, _server) do
    put_state(component,
      style: dark_style(),
      tiles: @tiles,
      last: "",
      filter_europe: false,
      fill_colour: "#334155"
    )
  end

  def template do
    ~HOLO"""
    <h1>Vector tiles</h1>
    <p>
      A <code>HoloMap.Source.Vector</code> feeding a fill and a line layer. Layers on a vector
      source must name a <code>source_layer</code>. A vector tile carries several, and MapLibre
      cannot guess which one is meant.
    </p>
    <p>
      The style below is an inline map rather than a URL, which is all a style has to be: a
      background layer and nothing else. Everything you see on top of it comes from the
      components.
    </p>
    <p>
      The globe button switches the projection. Mercator inflates everything far from the
      equator, which is the wrong story for a world view. Press it and the distortion goes.
    </p>

    <div class="controls">
      <button $click={:toggle_filter}>{Demo.VectorPage.filter_label(@filter_europe)}</button>
      <button $click={:set_colour, colour: "#334155"}>Slate</button>
      <button $click={:set_colour, colour: "#166534"}>Green</button>
      <button $click={:reset_view}>Reset view</button>
    </div>

    <p>
      The row below reaches MapLibre directly through <code>HoloMap.API</code>. Nothing it does
      survives the next declarative change. Press a colour button afterwards and the imperative
      paint is gone, because the reconciler treats the rendered props as the truth.
    </p>

    <div class="controls">
      <button $click={:flash_paint}>Flash amber (imperative)</button>
      <button $click={:hide_outline}>Hide outline (imperative)</button>
      <button $click={:filter_asia}>Filter to Asia (imperative)</button>
      <button $click={:swap_style}>Swap style (imperative)</button>
      <span>{@last}</span>
    </div>

    <HoloMap.Map
      cid="vector"
      style={@style}
      center={{10.0, 48.0}}
      zoom={3}
      height="480px"
      class="map"
      attribution_control={false}
    >
      <HoloMap.Source.Vector id="demo" url={@tiles} max_zoom={5} />

      <HoloMap.Layer.Fill
        id="countries-fill"
        source="demo"
        source_layer="countries"
        filter={Demo.VectorPage.europe_filter(@filter_europe)}
        paint={%{fill_color: @fill_colour, fill_opacity: 0.8}}
      />

      <HoloMap.Layer.Line
        id="countries-outline"
        source="demo"
        source_layer="countries"
        layout={%{line_cap: "round", line_join: "round"}}
        paint={%{line_color: "#94a3b8", line_width: 0.8}}
      />

      <HoloMap.Control.Navigation position="top-right" />
      <HoloMap.Control.Globe position="top-right" />
      <HoloMap.Control.Attribution
        position="bottom-right"
        compact
        custom_attribution="© MapLibre demo tiles"
      />
    </HoloMap.Map>
    """
  end

  @doc false
  def filter_label(true), do: "Show all countries"
  def filter_label(false), do: "Filter to Europe"

  @doc false
  def europe_filter(false), do: nil
  def europe_filter(true), do: ["==", ["get", "REGION_UN"], "Europe"]

  def action(:toggle_filter, _params, component) do
    put_state(component, :filter_europe, !component.state.filter_europe)
  end

  def action(:set_colour, params, component) do
    put_state(component, :fill_colour, params.colour)
  end

  def action(:flash_paint, _params, component) do
    HoloMap.API.set_paint_property("vector", "countries-fill", :fill_color, "#b45309")
    put_state(component, :last, "set_paint_property")
  end

  def action(:hide_outline, _params, component) do
    HoloMap.API.set_layout_property("vector", "countries-outline", :visibility, "none")
    put_state(component, :last, "set_layout_property")
  end

  def action(:filter_asia, _params, component) do
    HoloMap.API.set_filter("vector", "countries-fill", ["==", ["get", "REGION_UN"], "Asia"])
    put_state(component, :last, "set_filter")
  end

  # A style swap discards every source and layer MapLibre knows about. The
  # reconciler re-declares the ones it owns on the next style.load, which is
  # what makes this survivable at all.
  def action(:swap_style, _params, component) do
    HoloMap.API.set_style("vector", "https://demotiles.maplibre.org/style.json")
    put_state(component, :last, "set_style")
  end

  def action(:reset_view, _params, component) do
    HoloMap.API.ease_to("vector", center: {10.0, 48.0}, zoom: 3, bearing: 0, pitch: 0)
    component
  end

  # A style is a map, not necessarily a URL. This one draws a background and
  # nothing else, so every visible feature comes from the components above.
  defp dark_style do
    %{
      "version" => 8,
      "sources" => %{},
      "layers" => [
        %{
          "id" => "background",
          "type" => "background",
          "paint" => %{"background-color" => "#0f172a"}
        }
      ]
    }
  end
end
