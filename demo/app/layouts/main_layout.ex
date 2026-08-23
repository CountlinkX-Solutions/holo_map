defmodule Demo.MainLayout do
  use Hologram.Component

  alias Hologram.UI.Link
  alias Hologram.UI.Runtime

  prop :page_title, :string, default: "HoloMap demo"

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@page_title}</title>
        <link rel="stylesheet" href="/assets/maplibre-gl.css" />
        <link rel="stylesheet" href="/assets/demo.css" />
        <Runtime />
      </head>
      <body>
        <header class="topbar">
          <strong>HoloMap</strong>
          <nav>
            <Link to={Demo.HomePage}>Index</Link>
            <Link to={Demo.BasicPage}>Basic</Link>
            <Link to={Demo.GeoJSONPage}>GeoJSON</Link>
            <Link to={Demo.MarkersPage}>Markers</Link>
            <Link to={Demo.ClusteringPage}>Clustering</Link>
            <Link to={Demo.CameraPage}>Camera</Link>
          </nav>
        </header>
        <main>
          <slot />
        </main>
      </body>
    </html>
    """
  end
end
