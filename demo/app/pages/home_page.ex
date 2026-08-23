defmodule Demo.HomePage do
  use Hologram.Page

  alias Hologram.UI.Link

  route "/"
  layout Demo.MainLayout, page_title: "HoloMap", active: :index

  # A flat index in two flowing columns. The sidebar already carries the
  # taxonomy; repeating it here only produced a grid with a hole in it where
  # the one-item groups sat.
  @entries [
    {Demo.BasicPage, "Basic map",
     "The container, sizing, controls, and a camera driven by component state."},
    {Demo.GeoJSONPage, "GeoJSON layers",
     "One source feeding several layers, with live paint changes, filters and click events."},
    {Demo.VectorPage, "Vector tiles",
     "A vector source with fill and line layers over an inline style, plus a runtime filter."},
    {Demo.RasterPage, "Raster and image sources",
     "OpenStreetMap tiles with a radar image pinned on top, stepped frame by frame."},
    {Demo.HeatmapPage, "Heatmap",
     "Six thousand earthquakes, fading between a heat surface and individual circles."},
    {Demo.ClusteringPage, "Clustering",
     "A clustered source with separate cluster and single-point layers."},
    {Demo.MarkersPage, "Markers and popups",
     "Default pins, custom slot markup, dragging, and a popup driven by state."},
    {Demo.TerrainPage, "Terrain, hillshade and sky",
     "One elevation source driving 3D terrain, shaded relief and an atmosphere."},
    {Demo.ExtrusionPage, "3D extrusion",
     "Real OpenStreetMap buildings over a basemap, and geometry the application builds itself."},
    {Demo.CameraPage, "Camera API",
     "The escape hatch for camera moves that are events rather than state."}
  ]

  def template do
    ~HOLO"""
    <h1>HoloMap</h1>
    <p>
      MapLibre GL JS components for Hologram. Every page here exercises one part of the library
      against data published by MapLibre's own documentation, so none of it needs an API key.
    </p>

    <ul class="mt-12 gap-x-12 sm:columns-2">
      {%for {page, title, blurb} <- Demo.HomePage.entries()}
        <li class="mb-7 break-inside-avoid border-t border-zinc-200 pt-4 dark:border-zinc-800">
          <Link
            to={page}
            class="!font-medium !text-zinc-900 !no-underline hover:!text-accent-700 dark:!text-zinc-100 dark:hover:!text-accent-400"
          >{title}</Link>
          <p class="mt-1 max-w-[44ch] text-sm leading-6 text-zinc-600 dark:text-zinc-400">
            {blurb}
          </p>
        </li>
      {/for}
    </ul>
    """
  end

  @doc false
  def entries, do: @entries
end
