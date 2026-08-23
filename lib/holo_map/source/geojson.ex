defmodule HoloMap.Source.GeoJSON do
  @moduledoc """
  GeoJSON features, given inline or fetched from a URL.

      <HoloMap.Source.GeoJSON id="parcels" data={@feature_collection} />
      <HoloMap.Source.GeoJSON id="stops" data="/api/stops.geojson" cluster cluster_radius={60} />

  This is the source to reach for when the data comes from your own
  application. `data` is a plain Elixir map — build it in a command, put it in
  state, and the map follows:

      def command(:load_parcels, params, server) do
        put_action(server, :parcels_loaded, parcels: Repo.geojson(params.bbox))
      end

      def action(:parcels_loaded, params, component) do
        put_state(component, :parcels, params.parcels)
      end

  Changing `data` is the one source update that costs nothing structurally —
  MapLibre's `setData` swaps the features in place, leaving every layer built
  on top of it untouched.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** Referenced by layers' `source` prop |
  | `data` | map or string | **Required.** A GeoJSON object, or a URL to fetch one from |
  | `cluster` | boolean | Group nearby points into clusters |
  | `cluster_radius` | number | Cluster radius in pixels, default 50 |
  | `cluster_max_zoom` | number | Zoom past which clustering stops |
  | `cluster_min_points` | number | Points needed to form a cluster |
  | `cluster_properties` | map | Aggregations computed per cluster |
  | `max_zoom` | number | Maximum zoom to tile the data at |
  | `buffer` | number | Tile buffer in pixels |
  | `tolerance` | number | Douglas-Peucker simplification tolerance |
  | `line_metrics` | boolean | Required by `line_gradient` paint |
  | `generate_id` | boolean | Auto-assign feature ids, needed for feature state |
  | `promote_id` | string or map | Use a property as the feature id instead |
  | `filter` | list | Filter applied before tiling |
  | `attribution` | string | Attribution text |

  ## Clustering

  Clustered sources emit two kinds of feature, and they usually want two
  layers: one for clusters, one for the leftover single points.

      <HoloMap.Source.GeoJSON id="stops" data={@stops} cluster cluster_radius={60} />

      <HoloMap.Layer.Circle
        id="clusters"
        source="stops"
        filter={["has", "point_count"]}
        paint={%{circle_color: "#51bbd6", circle_radius: 18}}
      />

      <HoloMap.Layer.Circle
        id="unclustered"
        source="stops"
        filter={["!", ["has", "point_count"]]}
        paint={%{circle_color: "#11b4da", circle_radius: 6}}
      />

  ## Feature state

  `HoloMap.API.set_feature_state/3` needs every feature to have an id. GeoJSON
  features often do not carry one, so set `generate_id` or point `promote_id`
  at a property that is already unique.
  """

  use HoloMap.Def

  @keys [
    data: "data",
    max_zoom: "maxzoom",
    attribution: "attribution",
    buffer: "buffer",
    tolerance: "tolerance",
    cluster: "cluster",
    cluster_radius: "clusterRadius",
    cluster_max_zoom: "clusterMaxZoom",
    cluster_min_points: "clusterMinPoints",
    cluster_properties: "clusterProperties",
    line_metrics: "lineMetrics",
    generate_id: "generateId",
    promote_id: "promoteId",
    filter: "filter"
  ]

  prop :id, :string, required: true
  prop :data, :any, required: true
  prop :cluster, :any, default: nil
  prop :cluster_radius, :any, default: nil
  prop :cluster_max_zoom, :any, default: nil
  prop :cluster_min_points, :any, default: nil
  prop :cluster_properties, :map, default: nil
  prop :max_zoom, :any, default: nil
  prop :buffer, :any, default: nil
  prop :tolerance, :any, default: nil
  prop :line_metrics, :any, default: nil
  prop :generate_id, :any, default: nil
  prop :promote_id, :any, default: nil
  prop :filter, :list, default: nil
  prop :attribution, :string, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="source"
      data-hm-key={@id}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Source.build(%{
        data: @data,
        max_zoom: @max_zoom,
        attribution: @attribution,
        buffer: @buffer,
        tolerance: @tolerance,
        cluster: @cluster,
        cluster_radius: @cluster_radius,
        cluster_max_zoom: @cluster_max_zoom,
        cluster_min_points: @cluster_min_points,
        cluster_properties: @cluster_properties,
        line_metrics: @line_metrics,
        generate_id: @generate_id,
        promote_id: @promote_id,
        filter: @filter
      }, HoloMap.Source.GeoJSON.__keys__(), "geojson", [:cluster, :line_metrics, :generate_id])}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
