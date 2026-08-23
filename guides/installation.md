# Installation

`HoloMap` needs three things from the application that uses it: the Elixir
dependency, the `maplibre-gl` npm package, and two static files served at a URL
it can reach. Only the first is automatic.

The reason is structural. Hologram resolves bare import specifiers such as `"maplibre-gl"`
against the **host application's** `assets/package.json`, and its compiler
npm-installs only its own. A library has no way to reach into either.

## Prerequisites

Hologram 0.11 sets the floor, and it is a high one:

| | Minimum |
| --- | --- |
| Elixir | 1.19 |
| OTP | 28.1 |
| Node.js | 20 |
| A working Phoenix application | any |

With `asdf`:

```console
$ asdf install erlang 28.5
$ asdf install elixir 1.19.5-otp-28
```

Live reload also needs a filesystem watcher. On Linux that is `inotify-tools`,
and without it `mix holo` dies at startup with a `MatchError` on `:ignore`:

```console
$ sudo apt install inotify-tools     # Debian/Ubuntu
```

## 1. Add the dependency

```elixir
def deps do
  [
    {:hologram, "~> 0.11"},
    {:holo_map, "~> 0.1"}
  ]
end
```

Follow Hologram's own [installation guide](https://hologram.page/docs/installation)
for the compiler entry, the router plug, the static path and the formatter, all
of which belong to the application that owns the Phoenix endpoint, not to
`HoloMap`.

## 2. Install MapLibre

```console
$ npm install --prefix assets maplibre-gl@^6.5.0
```

Add it to a `setup` alias so a fresh checkout does not silently skip it:

```elixir
defp aliases do
  [
    setup: ["deps.get", "assets.install", "compile", "assets.copy"],
    "assets.install": &install_npm_deps/1,
    "assets.copy": &copy_static_assets/1
  ]
end

defp install_npm_deps(_args) do
  {_output, 0} = System.cmd("npm", ["install", "--prefix", "assets"], into: IO.stream())
end
```

## 3. Serve MapLibre's worker

**This step is not optional, and skipping it fails silently.**

MapLibre parses tiles in a Web Worker that it builds by importing
`maplibre-gl-worker.mjs`, resolved relative to its own module URL. Hologram
bundles MapLibre into a page bundle under `/hologram/`, so that resolution lands
on a file which is not there, and the failure happens inside a worker, where
nothing reports it. What you see is a map that renders its background, logs
nothing at all, and never draws a single tile.

Copy the worker and the shared chunk it imports into your static assets:

```elixir
defp copy_static_assets(_args) do
  dist = "assets/node_modules/maplibre-gl/dist"
  File.mkdir_p!("priv/static/assets")

  for file <- ~w(maplibre-gl.css maplibre-gl-worker.mjs maplibre-gl-shared.mjs) do
    File.cp!(Path.join(dist, file), Path.join("priv/static/assets", file))
  end
end
```

`HoloMap.Map` defaults `worker_url` to `"/assets/maplibre-gl-worker.mjs"`. If
they live elsewhere, set the prop:

```elixir
<HoloMap.Map cid="explorer" style={@style} worker_url="/static/js/maplibre-gl-worker.mjs" />
```

Both files must sit **next to each other**: the worker imports the shared chunk
by relative path.

## 4. Load the stylesheet

MapLibre's controls, markers and popups are unstyled without it. In your layout:

```elixir
<link rel="stylesheet" href="/assets/maplibre-gl.css" />
```

Or, if your application has a CSS pipeline, import it there instead:

```css
@import "maplibre-gl/dist/maplibre-gl.css";
```

## Serving the bundles

MapLibre is a big library, and Hologram builds **one bundle per page**. A page
that uses `HoloMap` therefore carries its own copy, around 1 MB minified, and
five such pages are five distinct 1 MB downloads, not one cached download reused
five times. That is inherent to Hologram's page-bundle model, not something this
library can avoid.

What it does mean is that the three settings below matter more here than in a
typical Phoenix application. In this demo they take a six-page tour from
**8.5 MB to 2.8 MB**.

### Compress the bundles

Bandit and Cowboy both compress responses on the fly, but `Plug.Static` answers
with `send_file/3` and a sendfile cannot be compressed in flight. So a 1.06 MB
bundle goes out at 1.06 MB rather than the 0.26 MB it gzips to, a 4× cost that
is easy to miss, because HTML responses from the same server *are* compressed.

Pre-compress after every build and set `gzip: true`:

```elixir
defp gzip_static_assets(_args) do
  for path <- Path.wildcard("priv/static/hologram/*.{js,map}") do
    File.write!(path <> ".gz", :zlib.gzip(File.read!(path)))
  end
end
```

It has to run *after* the Hologram compiler, which rewrites
`priv/static/hologram` on every build, and in `dev`/`test` that compiler is a
no-op unless `HOLOGRAM_START=1` is set. `mix holo` sets it, but `mix holo`
starts the server and never returns, so a gzip step ordered after it never
runs and one ordered before it compresses the *previous* build. Force the
compile yourself, then compress:

```elixir
defp build_bundles(_args) do
  System.put_env("HOLOGRAM_START", "1")
  Mix.Task.rerun("compile")
end
```

Hologram does not delete a superseded bundle, so old `.gz` files linger next to
bundles that no longer exist; clean the orphans in the same step.

### Cache them forever

Hologram names every bundle by content hash, so the bytes behind a given URL
never change. `Plug.Static`'s default is `cache-control: public` with no
`max-age`, which makes the browser revalidate on every navigation: cheap when
it answers 304, and a full re-download whenever a proxy or a devtools
"Disable cache" tick removes that conditional.

Give the bundles their own `Plug.Static` so the policy does not leak onto
unhashed filenames in `/assets`:

```elixir
plug Plug.Static,
  at: "/hologram",
  from: {:my_app, "priv/static/hologram"},
  gzip: true,
  cache_control_for_etags: "public, max-age=31536000, immutable"
```

### Do not serve sourcemaps in production

esbuild writes a sourcemap beside every bundle, and they are about five times
the size of the code, 28 MB across this demo. Only a browser with devtools open
requests one, so they cost nothing in normal use and everything the moment
someone opens the network tab. Keep them in development, refuse them elsewhere:

```elixir
plug :reject_sourcemaps

defp reject_sourcemaps(conn, _opts) do
  if String.ends_with?(conn.request_path, ".map") and
       not Application.get_env(:my_app, :serve_sourcemaps, false) do
    conn |> send_resp(404, "") |> halt()
  else
    conn
  end
end
```

`demo/lib/demo_web/endpoint.ex` has all three wired up if you want a reference.

## Umbrella projects

npm packages live in an `assets` directory at the **umbrella root**, and are
resolved from there for every child app. The child that owns the endpoint takes
the Hologram compiler entry; a child that only defines pages and components
takes the dependency alone.

## Checking it worked

```elixir
defmodule MyAppWeb.MapPage do
  use Hologram.Page

  route "/map"
  layout MyAppWeb.Layout

  def init(_params, component, _server) do
    put_state(component, :style, "https://demotiles.maplibre.org/style.json")
  end

  def template do
    ~HOLO"""
    <HoloMap.Map cid="check" style={@style} center={{0.0, 20.0}} zoom={2} height="400px">
      <HoloMap.Control.Navigation />
    </HoloMap.Map>
    """
  end
end
```

You should get a world map with zoom buttons. If you get a coloured rectangle
with no countries in it, step 3 is the one to revisit.

## Troubleshooting

| Symptom | Cause |
| ------- | ----- |
| Background renders, no tiles ever, clean console | The worker is not being served, see step 3 |
| Nothing at all, container has zero height | `height` was set to `nil` without CSS taking over |
| `boolean expected, string found` from MapLibre | A boolean prop this library does not yet coerce. Pass `={true}` explicitly and please report it |
| `Hologram.PropError` naming a `HoloMap` component | A required prop is missing at that call site |
| `a HoloMap definition component was rendered outside a <HoloMap.Map>` | A source, layer, marker, popup or control is not nested inside a map |
| `mix holo` exits with `MatchError` on `:ignore` | The filesystem watcher is missing, see Prerequisites |
| Browser cannot reach `localhost` but `curl` can | The endpoint is listening on IPv4 only while `localhost` resolves to `::1` |
