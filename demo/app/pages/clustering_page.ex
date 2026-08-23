defmodule Demo.ClusteringPage do
  use Hologram.Page

  route "/clustering"
  layout Demo.MainLayout, page_title: "Clustering — HoloMap"

  @style_url "https://demotiles.maplibre.org/style.json"

  def init(_params, component, _server) do
    put_state(component,
      style: @style_url,
      points: points(),
      radius: 50
    )
  end

  def template do
    ~HOLO"""
    <h1>Clustering</h1>
    <p>
      A clustered source emits two kinds of feature, so it wants two layers: one filtered
      to <code>["has", "point_count"]</code> and one to its negation. Changing the cluster
      radius is a structural change to the source, so the reconciler detaches these layers,
      rebuilds the source and puts them back — watch them survive it.
    </p>

    <div class="controls">
      <button $click={:set_radius, radius: 30}>Radius 30</button>
      <button $click={:set_radius, radius: 50}>Radius 50</button>
      <button $click={:set_radius, radius: 90}>Radius 90</button>
      <span>radius: {@radius}</span>
    </div>

    <HoloMap.Map cid="clusters" style={@style} center={{-70.0, 19.0}} zoom={7}
                 height="480px" class="map">
      <HoloMap.Source.GeoJSON
        id="points"
        data={@points}
        cluster
        cluster_radius={@radius}
        cluster_max_zoom={12}
      />

      <HoloMap.Layer.Circle
        id="cluster-circles"
        source="points"
        filter={["has", "point_count"]}
        paint={%{
          circle_color: ["step", ["get", "point_count"], "#51bbd6", 10, "#f1f075", 25, "#f28cb1"],
          circle_radius: ["step", ["get", "point_count"], 16, 10, 22, 25, 30],
          circle_opacity: 0.85
        }}
      />

      <HoloMap.Layer.Symbol
        id="cluster-counts"
        source="points"
        filter={["has", "point_count"]}
        layout={%{text_field: ["get", "point_count_abbreviated"], text_size: 12}}
        paint={%{text_color: "#0b3d52"}}
      />

      <HoloMap.Layer.Circle
        id="single-points"
        source="points"
        filter={["!", ["has", "point_count"]]}
        paint={%{
          circle_color: "#11b4da",
          circle_radius: 5,
          circle_stroke_color: "#ffffff",
          circle_stroke_width: 1
        }}
      />
    </HoloMap.Map>
    """
  end

  def action(:set_radius, params, component) do
    put_state(component, :radius, params.radius)
  end

  # A deterministic scatter, so the page looks the same on every render and in
  # every screenshot. Hologram compiles this to the client, where :rand would
  # produce a different cloud on each pass.
  defp points do
    features =
      for i <- 0..179 do
        lng = -72.0 + rem(i * 37, 400) / 100.0
        lat = 17.6 + rem(i * 53, 260) / 100.0

        %{
          "type" => "Feature",
          "properties" => %{"id" => i},
          "geometry" => %{"type" => "Point", "coordinates" => [lng, lat]}
        }
      end

    %{"type" => "FeatureCollection", "features" => features}
  end
end
