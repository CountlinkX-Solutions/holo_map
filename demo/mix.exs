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
      setup: [
        "deps.get",
        "assets.install",
        "assets.build",
        "assets.copy",
        "assets.css",
        "assets.gzip"
      ],
      # Hologram npm-installs its own assets/package.json, never the host
      # application's — it only puts assets/node_modules on esbuild's NODE_PATH.
      # Installing maplibre-gl is therefore this app's job.
      "assets.install": &install_npm_deps/1,
      # Hologram bundles the JavaScript itself. The only static assets this app
      # owns are two stylesheets, one of which npm put in node_modules during
      # compilation — so this runs after compile, not before.
      "assets.copy": &copy_static_assets/1,
      "assets.css": &build_css/1,
      # `mix holo` starts the server and never returns, so everything that has to
      # touch the bundles must run before it — and the bundles only exist after a
      # compile with the Hologram compiler enabled, which `assets.build` forces.
      # Ordering gzip before that step compresses the *previous* build and leaves
      # the new one uncompressed.
      server: [
        "assets.install",
        "assets.build",
        "assets.copy",
        "assets.css",
        "assets.gzip",
        "holo"
      ],
      "assets.build": &build_bundles/1,
      # Pre-compression has to run after the Hologram compiler, which rewrites
      # priv/static/hologram on every build.
      "assets.gzip": &gzip_static_assets/1
    ]
  end

  # In dev and test the Hologram compiler is a no-op unless HOLOGRAM_START is
  # set — `mix holo` sets it, but by then it is too late for any task that needs
  # the bundles on disk.
  defp build_bundles(_args) do
    System.put_env("HOLOGRAM_START", "1")
    Mix.Task.rerun("compile")
  end

  defp install_npm_deps(_args) do
    {_output, status} = System.cmd("npm", ["install", "--prefix", "assets"], into: IO.stream())

    if status != 0 do
      Mix.raise("npm install failed in assets/")
    end
  end

  defp build_css(_args) do
    File.mkdir_p!("priv/static/assets/fonts")

    for {from, to} <- [
          {"assets/node_modules/@fontsource-variable/geist/files/geist-latin-wght-normal.woff2",
           "priv/static/assets/fonts/geist.woff2"},
          {"assets/node_modules/@fontsource-variable/geist-mono/files/geist-mono-latin-wght-normal.woff2",
           "priv/static/assets/fonts/geist-mono.woff2"}
        ] do
      File.cp!(from, to)
    end

    {_output, status} =
      System.cmd(
        Path.expand("assets/node_modules/.bin/tailwindcss"),
        ["-i", "app.css", "-o", "../priv/static/assets/app.css", "--minify"],
        cd: "assets",
        into: IO.stream()
      )

    if status != 0, do: Mix.raise("tailwind build failed")

    gzip_file("priv/static/assets/app.css")
  end

  # Every asset with a stable filename compresses itself as it is written.
  #
  # Plug.Static with gzip: true prefers a sibling .gz, and unlike the Hologram
  # bundles these filenames do not carry a content hash. So a .gz left behind by
  # an earlier build is served for the current URL, silently, and the change you
  # just made never reaches the browser. Keeping compression in the same step
  # that writes the file makes the two impossible to separate.
  defp gzip_file(path) do
    File.write!(path <> ".gz", :zlib.gzip(File.read!(path)))
  end

  defp gzip_static_assets(_args) do
    # Hologram never deletes a superseded bundle, so its .gz would linger and
    # accumulate alongside it.
    for orphan <- Path.wildcard("priv/static/hologram/*.gz"),
        not File.exists?(String.replace_suffix(orphan, ".gz", "")) do
      File.rm!(orphan)
    end

    paths =
      Path.wildcard("priv/static/hologram/*.{js,map}") ++
        Path.wildcard("priv/static/assets/*.{js,css,mjs}")

    saved =
      Enum.reduce(paths, 0, fn path, acc ->
        raw = File.read!(path)
        compressed = :zlib.gzip(raw)
        File.write!(path <> ".gz", compressed)
        acc + byte_size(raw) - byte_size(compressed)
      end)

    Mix.shell().info(
      "gzipped #{length(paths)} files, saving #{div(saved, 1024)} KB over the wire"
    )
  end

  defp copy_static_assets(_args) do
    File.mkdir_p!("priv/static/assets")

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
        target = Path.join("priv/static/assets", to)
        File.cp!(Path.join(dist, from), target)
        if Path.extname(target) in [".css", ".mjs"], do: gzip_file(target)
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
