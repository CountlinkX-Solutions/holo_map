defmodule Demo.HomePage do
  use Hologram.Page

  alias Hologram.UI.Link

  route "/"
  layout Demo.MainLayout, page_title: "HoloMap demo"

  def template do
    ~HOLO"""
    <h1>HoloMap</h1>
    <p>
      MapLibre GL JS components for Hologram. Each page below exercises one part of the
      library against MapLibre's public demo tiles, so nothing here needs an API key.
    </p>

    <ul class="index">
      <li>
        <Link to={Demo.BasicPage}>Basic map</Link>
        — the container, sizing, controls, and a camera driven by component state.
      </li>
      <li>
        <Link to={Demo.GeoJSONPage}>GeoJSON layers</Link>
        — one source feeding several layers, live paint changes, filters, and click events
        coming back as Hologram actions.
      </li>
      <li>
        <Link to={Demo.MarkersPage}>Markers and popups</Link>
        — default pins, custom slot markup, draggable markers, and a popup driven by state.
      </li>
      <li>
        <Link to={Demo.ClusteringPage}>Clustering</Link>
        — a clustered source with separate cluster and single-point layers.
      </li>
      <li>
        <Link to={Demo.CameraPage}>Camera API</Link>
        — the imperative escape hatch: fly_to, fit_bounds, and feature state.
      </li>
    </ul>
    """
  end
end
