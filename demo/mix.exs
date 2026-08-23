defmodule Demo.MixProject do
  use Mix.Project

  def project do
    [
      app: :demo,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Only the app that owns the Phoenix endpoint takes the Hologram
      # compiler. The holo_map library deliberately does not — its components
      # are discovered and bundled when this app compiles.
      compilers: Mix.compilers() ++ [:hologram],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader],
      deps: deps()
    ]
  end

  def application do
    [mod: {Demo.Application, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["app", "lib", "test/support"]
  defp elixirc_paths(_env), do: ["app", "lib"]

  defp aliases do
    [
      setup: ["deps.get", "assets.install", "compile", "assets.copy"],
      # Hologram npm-installs its own assets/package.json, never the host
      # application's — it only puts assets/node_modules on esbuild's NODE_PATH.
      # Installing maplibre-gl is therefore this app's job.
      "assets.install": &install_npm_deps/1,
      # Hologram bundles the JavaScript itself. The only static assets this app
      # owns are two stylesheets, one of which npm put in node_modules during
      # compilation — so this runs after compile, not before.
      "assets.copy": &copy_static_assets/1,
      server: ["assets.install", "compile", "assets.copy", "holo"]
    ]
  end

  defp install_npm_deps(_args) do
    {_output, status} = System.cmd("npm", ["install", "--prefix", "assets"], into: IO.stream())

    if status != 0 do
      Mix.raise("npm install failed in assets/")
    end
  end

  defp copy_static_assets(_args) do
    File.mkdir_p!("priv/static/assets")
    File.cp!("assets/demo.css", "priv/static/assets/demo.css")

    dist = "assets/node_modules/maplibre-gl/dist"

    # The worker and the shared chunk it imports have to sit next to each other
    # and be reachable at the URL HoloMap.Map's `worker_url` prop points at —
    # MapLibre's own resolution of them breaks once the library is bundled.
    copies = [
      {"maplibre-gl.css", "maplibre-gl.css"},
      {"maplibre-gl-worker.mjs", "maplibre-gl-worker.mjs"},
      {"maplibre-gl-shared.mjs", "maplibre-gl-shared.mjs"},
      # Both .mjs files reference a sourcemap; without them devtools requests
      # produce a stream of 404s in the server log.
      {"maplibre-gl-worker.mjs.map", "maplibre-gl-worker.mjs.map"},
      {"maplibre-gl-shared.mjs.map", "maplibre-gl-shared.mjs.map"}
    ]

    if File.exists?(Path.join(dist, "maplibre-gl.css")) do
      Enum.each(copies, fn {from, to} ->
        File.cp!(Path.join(dist, from), Path.join("priv/static/assets", to))
      end)
    else
      Mix.shell().error("""
      MapLibre assets not found in #{dist}.
      Run `mix assets.install` first.
      """)
    end
  end

  defp deps do
    [
      {:holo_map, path: ".."},
      {:hologram, "~> 0.11"},
      {:bandit, "~> 1.5"}
    ]
  end
end
