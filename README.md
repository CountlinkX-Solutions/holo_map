# HoloMap

[![Hex.pm](https://img.shields.io/hexpm/v/holo_map.svg)](https://hex.pm/packages/holo_map)
[![Documentation](https://img.shields.io/badge/hexdocs-holo__map-8e7cc3)](https://hexdocs.pm/holo_map)
[![CI](https://github.com/CountlinkX-Solutions/holo_map/actions/workflows/ci.yml/badge.svg)](https://github.com/CountlinkX-Solutions/holo_map/actions/workflows/ci.yml)

Declarative [MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/) map components for the
[Hologram](https://hologram.page) Elixir framework.

A map is a component tree. Sources, layers, markers and controls are components; what they look
like is component state; what happens on them comes back as Hologram actions.

```elixir
<HoloMap.Map cid="explorer" style={@style_url} center={{-70.66, 19.45}} zoom={11}>
  <HoloMap.Source.GeoJSON id="parcels" data={@parcels} />

  <HoloMap.Layer.Fill
    id="parcels-fill"
    source="parcels"
    paint={%{fill_color: @colour, fill_opacity: 0.4}}
    on_click={:parcel_clicked}
  />

  <HoloMap.Control.Navigation position="top-right" />
</HoloMap.Map>
```

```elixir
def action(:parcel_clicked, params, component) do
  case params.features do
    [%{properties: %{parcel_id: id}} | _rest] -> put_state(component, :selected, id)
    [] -> component
  end
end
```

Changing `@colour` calls `setPaintProperty` on the live layer. Nothing is rebuilt, nothing
flickers, and there is no JavaScript in your application.

## What is in the box

| Group | Components |
| ----- | ---------- |
| Container | `HoloMap.Map` |
| Sources | `GeoJSON`, `Vector`, `Raster`, `RasterDEM`, `Image` |
| Layers | `Fill`, `Line`, `Circle`, `Symbol`, `Raster`, `Heatmap`, `Hillshade`, `FillExtrusion`, plus a generic `Layer` |
| Overlays | `Marker`, `Popup` |
| Images | `Image`, for registering your own icons and patterns |
| Controls | `Navigation`, `Scale`, `Geolocate`, `Fullscreen`, `Attribution`, `Globe`, `Terrain` |
| 3D | `Terrain`, `Sky` |
| Imperative | `HoloMap.API`: `fly_to/2`, `fit_bounds/3`, `set_feature_state/3`, … |

## Requirements

- Elixir 1.19+, OTP 28.1+ (Hologram's own floor)
- Hologram 0.11+
- MapLibre GL JS 6.x, installed in the host application

## Installation

```elixir
def deps do
  [{:holo_map, "~> 0.1"}]
end
```

`HoloMap` cannot ship its npm dependency, because Hologram resolves bare import specifiers against the
*host application's* `assets/package.json`. Three steps, once per application, and the
[Installation guide](guides/installation.md) walks through them:

1. `npm install --prefix assets maplibre-gl@^6.5.0`
2. Serve `maplibre-gl-worker.mjs` and `maplibre-gl-shared.mjs` from `/assets/`. MapLibre's own
   resolution of its worker breaks once the library is bundled, and the failure is silent
3. Load `maplibre-gl.css`

## How it works

Hologram gives components an `init` hook but no "props changed" and no "about to unmount" hook,
and its JavaScript interop only runs inside action handlers. A map library needs all three.

So `HoloMap` does not drive MapLibre from Elixir call sites. Each child component renders one
hidden element carrying its MapLibre specification as JSON, and a reconciler in the browser
watches those elements with a `MutationObserver`:

```
<HoloMap.Layer.Fill paint={%{fill_color: @colour}} />
        │
        ▼  Hologram renders and re-renders this
<div data-hm="layer" data-hm-key="parcels-fill" data-hm-spec='{"type":"fill",…}'></div>
        │
        ▼  MutationObserver sees the attribute change
map.setPaintProperty("parcels-fill", "fill-color", "#ef4444")
```

Mount, update and unmount all fall out of that, without a framework hook for any of them, and it
works *with* Hologram's virtual DOM, which already preserves JavaScript-managed children. The
[Architecture guide](guides/architecture.md) goes into the consequences.

One practical upshot: almost all of `HoloMap` is pure Elixir that builds JSON, so almost all of it
is unit tested. Only `HoloMap.Runtime` touches JavaScript.

## Guides

- [Installation](guides/installation.md): the three steps `HoloMap` cannot do for you
- [Getting started](guides/getting-started.md): from an empty map to data, state and events
- [Architecture](guides/architecture.md): how a prop change becomes a MapLibre call, and what it costs
- [Events](guides/events.md): handler syntax, targets, and every payload
- [Imperative API](guides/imperative-api.md): the escape hatch, and when to reach for it
- [Limitations](guides/limitations.md): what does not work, and why

Every module also carries a full `@moduledoc` with prop tables and the reasoning behind the
awkward parts. Run `mix docs`, or start from `HoloMap`.

## Demo

`demo/` is a Phoenix + Hologram application exercising every component against MapLibre's public
demo tiles, so no API key is needed.

```console
$ mix demo.setup
$ mix server        # http://localhost:4000
```

Those run from the repository root. The demo is its own Mix project in `demo/`, so
`cd demo && mix setup && mix server` works too. The root aliases just save the `cd`.

Its browser test suite lives in `demo/test/browser/` and drives a real MapLibre instance through
Playwright. See the README there for what it covers and why.

## Continuous integration

Two workflows, split by what they depend on.

`ci.yml` runs on every push to `main` and on every pull request: compile with
warnings as errors, formatter, Credo strict, ExUnit, the runtime's unit tests
under Node (see the Architecture guide), docs, Dialyzer, and a build of the demo
with the Hologram compiler. The demo depends on the library by path, so that build
catches a change that breaks a component's template or props, or that uses
Elixir Hologram cannot run in the browser. It needs Hex and npm, and no browser
or tile server.

`browser.yml` runs the five Playwright suites weekly, and on demand. It is
deliberately not on every push: those suites drive a real MapLibre instance
against real tile servers, including OpenStreetMap's, whose usage policy asks
that automated traffic stay modest. Putting someone else's infrastructure in
this project's critical path would make the build fail for reasons unrelated to
the change. Weekly catches a MapLibre release or a moved asset; the manual
trigger covers a change that actually touches the runtime.

## Licence

MIT.
