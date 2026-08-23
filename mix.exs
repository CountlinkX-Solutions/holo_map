defmodule HoloMap.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/CountlinkX-Solutions/holo_map"
  @maplibre_version "6.5.0"

  def project do
    [
      app: :holo_map,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "HoloMap",
      source_url: @source_url,
      aliases: aliases(),
      test_coverage: [summary: [threshold: 0]],
      # Outside _build so CI can cache it across runs; building the PLT from
      # scratch costs more than every other check combined.
      dialyzer: [plt_local_path: "priv/plts", plt_core_path: "priv/plts"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:hologram, "~> 0.11"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  # The demo is a separate Mix project in demo/. These forward to it, so
  # `mix server` works from the repository root — which is where you are when
  # you have just been editing the library.
  defp aliases do
    [
      server: &demo("server", &1),
      "demo.setup": &demo("setup", &1),
      "demo.test": &demo_browser_test/1
    ]
  end

  defp demo(task, _args) do
    unless File.dir?("demo") do
      Mix.raise(
        "no demo/ directory here — these aliases only work in a checkout of the repository"
      )
    end

    {_output, status} = System.cmd("mix", [task], cd: "demo", into: IO.stream())

    if status != 0 do
      Mix.raise("mix #{task} failed in demo/ with exit status #{status}")
    end
  end

  defp demo_browser_test(_args) do
    {_output, status} = System.cmd("npm", ["test"], cd: "demo/test/browser", into: IO.stream())

    if status != 0 do
      Mix.raise("the browser suite failed — is `mix server` running in demo/?")
    end
  end

  defp description do
    "Declarative MapLibre GL JS map components for the Hologram Elixir framework."
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Yendris Rogelio Cruz Mendoza"],
      links: %{
        "GitHub" => @source_url,
        "MapLibre GL JS" => "https://maplibre.org/maplibre-gl-js/docs/"
      },
      # `.mjs` files live next to their Elixir modules so Hologram's `js_import`
      # can resolve them with a relative path. They must ship with the package.
      files: ~w(lib guides mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/installation.md",
        "guides/getting-started.md",
        "guides/architecture.md",
        "guides/events.md",
        "guides/imperative-api.md",
        "guides/limitations.md"
      ],
      groups_for_extras: [
        Guides: ~r"guides/"
      ],
      groups_for_modules: [
        "Map container": [HoloMap.Map],
        Sources: ~r"HoloMap\.Source",
        Layers: ~r"HoloMap\.Layer",
        Overlays: [HoloMap.Marker, HoloMap.Popup],
        Controls: ~r"HoloMap\.Control",
        "3D & terrain": [HoloMap.Terrain, HoloMap.Sky],
        "Imperative API": [HoloMap.API],
        Internals: [HoloMap.JSON, HoloMap.Spec, HoloMap.Event, HoloMap.Runtime]
      ],
      before_closing_body_tag: fn
        :html -> ~s(<!-- MapLibre GL JS #{@maplibre_version} -->)
        _ -> ""
      end
    ]
  end
end
