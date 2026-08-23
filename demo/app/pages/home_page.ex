defmodule Demo.HomePage do
  use Hologram.Page

  alias Hologram.UI.Link

  route "/"
  layout Demo.MainLayout, page_title: "HoloMap demo"

  def template do
    ~HOLO"""
    <h1>HoloMap</h1>
    <p>
      MapLibre GL JS components for Hologram. Every page below exercises one part of the
      library against data published by MapLibre's own documentation, so nothing here needs
      an API key.
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
        <Link to={Demo.VectorPage}>Vector tiles</Link>
        — a vector source with fill and line layers over an inline style, plus a runtime filter.
      </li>
      <li>
        <Link to={Demo.RasterPage}>Raster and image sources</Link>
        — OpenStreetMap tiles with a radar image pinned on top, stepped frame by frame.
      </li>
      <li>
        <Link to={Demo.HeatmapPage}>Heatmap</Link>
        — six thousand earthquakes, fading between a heat surface and individual circles.
      </li>
      <li>
        <Link to={Demo.TerrainPage}>Terrain, hillshade and sky</Link>
        — one elevation source driving 3D terrain, shaded relief and an atmosphere.
      </li>
      <li>
        <Link to={Demo.ExtrusionPage}>3D extrusion</Link>
        — real OpenStreetMap buildings raised over a basemap, and a second map on the same
        page extruding geometry the application builds itself.
      </li>
      <li>
        <Link to={Demo.CameraPage}>Camera API</Link>
        — the imperative escape hatch: fly_to, fit_bounds, and feature state.
      </li>
    </ul>
    """
  end
end
