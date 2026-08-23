defmodule Demo.GeoJSONPage do
  use Hologram.Page

  route "/geojson"
  layout Demo.MainLayout, page_title: "GeoJSON layers — HoloMap"

  @style_url "https://demotiles.maplibre.org/style.json"

  @cities [
    %{name: "Santo Domingo", lng: -69.93, lat: 18.48, region: "caribbean", population: 2_908_000},
    %{name: "Santiago", lng: -70.70, lat: 19.45, region: "caribbean", population: 691_000},
    %{name: "Havana", lng: -82.38, lat: 23.13, region: "caribbean", population: 2_130_000},
    %{name: "San Juan", lng: -66.11, lat: 18.47, region: "caribbean", population: 342_000},
    %{name: "Bogotá", lng: -74.07, lat: 4.71, region: "andes", population: 7_181_000},
    %{name: "Quito", lng: -78.47, lat: -0.18, region: "andes", population: 1_763_000},
    %{name: "Lima", lng: -77.04, lat: -12.05, region: "andes", population: 9_752_000}
  ]

  def init(_params, component, _server) do
    put_state(component,
      style: @style_url,
      cities: feature_collection(@cities),
      region: "all",
      colour: "#2563eb",
      selected: nil,
      hovered: nil
    )
  end

  def template do
    ~HOLO"""
    <h1>GeoJSON layers</h1>
    <p>
      One <code>HoloMap.Source.GeoJSON</code> feeding a circle layer and a label layer.
      The colour and the filter below are component state — changing them updates the
      existing layer through <code>setPaintProperty</code> and <code>setFilter</code>
      rather than rebuilding anything.
    </p>

    <div class="controls">
      <button $click={:set_region, region: "all"}>All</button>
      <button $click={:set_region, region: "caribbean"}>Caribbean</button>
      <button $click={:set_region, region: "andes"}>Andes</button>
      <button $click={:set_colour, colour: "#2563eb"}>Blue</button>
      <button $click={:set_colour, colour: "#dc2626"}>Red</button>
      <span>filter: {@region}</span>
    </div>

    <HoloMap.Map
      cid="cities"
      style={@style}
      center={{-74.0, 10.0}}
      zoom={3}
      height="480px"
      class="map"
    >
      <HoloMap.Source.GeoJSON id="cities" data={@cities} generate_id />

      <HoloMap.Layer.Circle
        id="cities-circles"
        source="cities"
        filter={Demo.GeoJSONPage.region_filter(@region)}
        paint={%{
          circle_color: @colour,
          circle_opacity: 0.75,
          circle_stroke_color: "#ffffff",
          circle_stroke_width: ["case", ["boolean", ["feature-state", "hover"], false], 4, 1.5],
          circle_radius: [
            "interpolate",
            ["linear"],
            ["get", "population"],
            300_000,
            6,
            10_000_000,
            26
          ]
        }}
        on_click={:city_clicked}
        on_mouse_move={:city_hovered}
        on_mouse_leave={:city_unhovered}
      />

      <HoloMap.Layer.Symbol
        id="cities-labels"
        source="cities"
        filter={Demo.GeoJSONPage.region_filter(@region)}
        layout={%{
          text_field: ["get", "name"],
          text_size: 12,
          text_offset: [0, 1.6],
          text_anchor: "top"
        }}
        paint={%{text_color: "#111827", text_halo_color: "#ffffff", text_halo_width: 1.5}}
      />
    </HoloMap.Map>

    <h2>Selection</h2>
    {%if @selected}
      <p>Clicked: <strong>{@selected}</strong></p>
    {%else}
      <p>Click a circle. The handler below is an ordinary Hologram action.</p>
    {/if}
    """
  end

  @doc false
  def region_filter("all"), do: nil
  def region_filter(region), do: ["==", ["get", "region"], region]

  def action(:set_region, params, component) do
    put_state(component, :region, params.region)
  end

  def action(:set_colour, params, component) do
    put_state(component, :colour, params.colour)
  end

  def action(:city_clicked, params, component) do
    case params.features do
      [%{properties: %{name: name}} | _rest] -> put_state(component, :selected, name)
      [] -> component
    end
  end

  # Feature state is the mechanism behind hover styling, and it belongs to a
  # feature rather than to a component — so it has no declarative equivalent.
  def action(:city_hovered, params, component) do
    case params.features do
      [%{id: id} | _rest] when not is_nil(id) ->
        clear_hover(component.state.hovered)
        HoloMap.API.set_feature_state("cities", %{source: "cities", id: id}, %{hover: true})
        put_state(component, :hovered, id)

      _other ->
        component
    end
  end

  def action(:city_unhovered, _params, component) do
    clear_hover(component.state.hovered)
    put_state(component, :hovered, nil)
  end

  defp clear_hover(nil), do: :ok

  defp clear_hover(id) do
    HoloMap.API.remove_feature_state("cities", %{source: "cities", id: id}, "hover")
  end

  defp feature_collection(cities) do
    %{
      "type" => "FeatureCollection",
      "features" =>
        Enum.map(cities, fn city ->
          %{
            "type" => "Feature",
            "properties" => %{
              "name" => city.name,
              "region" => city.region,
              "population" => city.population
            },
            "geometry" => %{"type" => "Point", "coordinates" => [city.lng, city.lat]}
          }
        end)
    }
  end
end
