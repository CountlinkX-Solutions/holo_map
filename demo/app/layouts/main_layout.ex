defmodule Demo.MainLayout do
  use Hologram.Component

  alias Hologram.UI.Link
  alias Hologram.UI.Runtime

  prop :page_title, :string, default: "HoloMap"
  prop :active, :atom, default: nil

  # Eleven destinations do not fit on one line at desktop, and a nav that wraps
  # to two lines is broken. Grouping them in a sidebar is what this actually is:
  # documentation you can click through.
  @sections [
    {"Start", [{:index, "Index", Demo.HomePage}, {:basic, "Basic", Demo.BasicPage}]},
    {"Data",
     [
       {:geojson, "GeoJSON", Demo.GeoJSONPage},
       {:vector, "Vector", Demo.VectorPage},
       {:raster, "Raster", Demo.RasterPage},
       {:heatmap, "Heatmap", Demo.HeatmapPage},
       {:clustering, "Clustering", Demo.ClusteringPage}
     ]},
    {"Overlays", [{:markers, "Markers", Demo.MarkersPage}]},
    {"Elevation",
     [{:terrain, "Terrain", Demo.TerrainPage}, {:extrusion, "Extrusion", Demo.ExtrusionPage}]},
    {"Imperative", [{:camera, "Camera", Demo.CameraPage}]}
  ]

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en" class="antialiased">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@page_title}</title>
        <link rel="stylesheet" href="/assets/maplibre-gl.css" />
        <link rel="stylesheet" href="/assets/app.css" />
        <Runtime />
      </head>
      <body class="min-h-screen bg-white font-sans text-zinc-800 dark:bg-zinc-950 dark:text-zinc-300">
        <div class="mx-auto flex max-w-[1500px] flex-col lg:flex-row">
          <aside class="shrink-0 border-zinc-200 lg:sticky lg:top-0 lg:h-screen lg:w-64 lg:overflow-y-auto lg:border-r dark:border-zinc-800">
            <div class="border-b border-zinc-200 px-6 py-5 lg:border-b-0 dark:border-zinc-800">
              <Link to={Demo.HomePage} class="block">
                <span class="font-mono text-sm font-semibold tracking-tight text-zinc-900 dark:text-zinc-50">HoloMap</span>
              </Link>
              <p class="mt-1 text-xs leading-relaxed text-zinc-600 dark:text-zinc-400">
                MapLibre components for Hologram
              </p>
            </div>

            <nav class="flex gap-6 overflow-x-auto px-6 py-3 lg:block lg:space-y-6 lg:overflow-visible lg:px-6 lg:py-6">
              {%for {group, entries} <- Demo.MainLayout.sections()}
                <div class="shrink-0">
                  <p class="hidden text-[11px] font-medium uppercase tracking-wider text-zinc-500 lg:block dark:text-zinc-400">
                    {group}
                  </p>
                  <ul class="flex gap-4 lg:mt-2 lg:block lg:gap-0 lg:space-y-0.5">
                    {%for {key, label, page} <- entries}
                      <li>
                        <Link
                          to={page}
                          class={Demo.MainLayout.link_class(key == @active)}
                        >{label}</Link>
                      </li>
                    {/for}
                  </ul>
                </div>
              {/for}
            </nav>

            <div class="hidden px-6 py-6 lg:block">
              <p class="border-t border-zinc-200 pt-5 font-mono text-[11px] leading-relaxed text-zinc-500 dark:border-zinc-800 dark:text-zinc-400">
                MapLibre GL JS 6.5<br />Hologram 0.11
              </p>
            </div>
          </aside>

          <main class="min-w-0 flex-1 px-6 py-10 lg:px-12 lg:py-16">
            <div class="page mx-auto max-w-5xl">
              <slot />
            </div>
          </main>
        </div>
      </body>
    </html>
    """
  end

  @doc false
  def sections, do: @sections

  @doc false
  def link_class(true) do
    "block px-2 py-1 text-sm font-medium text-accent-700 lg:-mx-2 lg:border-l-2 " <>
      "lg:border-accent-600 lg:pl-3 dark:text-accent-400 dark:lg:border-accent-400"
  end

  def link_class(false) do
    "block px-2 py-1 text-sm text-zinc-600 transition-colors hover:text-zinc-900 " <>
      "lg:-mx-2 lg:border-l-2 lg:border-transparent lg:pl-3 lg:hover:border-zinc-300 " <>
      "dark:text-zinc-400 dark:hover:text-zinc-100 dark:lg:hover:border-zinc-700"
  end
end
