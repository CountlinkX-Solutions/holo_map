# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `HoloMap.Map`, the map container. Stateful, keyed by its Hologram `cid`, which
  is also the DOM container id and the handle for every `HoloMap.API` call.
- Sources: `HoloMap.Source.GeoJSON`, `.Vector`, `.Raster`, `.RasterDEM`,
  `.Image`.
- Layers: `HoloMap.Layer.Fill`, `.Line`, `.Circle`, `.Symbol`, `.Raster`,
  `.Heatmap`, `.Hillshade`, `.FillExtrusion`, plus a generic `HoloMap.Layer`
  for a type decided at runtime.
- Overlays: `HoloMap.Marker` and `HoloMap.Popup`, both accepting slot content.
- Controls: `HoloMap.Control.Navigation`, `.Scale`, `.Geolocate`, `.Fullscreen`,
  `.Attribution`.
- 3D: `HoloMap.Terrain` and `HoloMap.Sky`.
- `HoloMap.API` — `fly_to/2`, `ease_to/2`, `jump_to/2`, `fit_bounds/3`,
  `resize/1`, `set_style/2`, `set_filter/3`, `set_paint_property/4`,
  `set_layout_property/4`, `set_feature_state/3`, `remove_feature_state/3`.
- MapLibre events surfaced as Hologram actions, with payloads documented per
  component and in the Events guide.
- `window.HoloMap.map/1`, so MapLibre plugins can reach the raw instance.
- A Phoenix + Hologram demo application exercising every component, and a
  Playwright suite driving a real MapLibre instance.

### Notes on the design

- Components do not call MapLibre. Each renders one hidden element carrying its
  specification as JSON, and a `MutationObserver` in the browser reconciles
  those elements against the live map. This is what supplies the mount, update
  and unmount hooks Hologram 0.11 does not have. See the Architecture guide.
- `HoloMap.JSON` exists because `Jason` cannot be compiled to JavaScript by
  Hologram, and specifications have to be encoded during client-side re-renders.
- `HoloMap.Map` sets MapLibre's worker URL explicitly. MapLibre resolves its
  worker against `import.meta.url`, which points at Hologram's page bundle once
  bundled; the resulting import failure happens inside a worker and surfaces as
  a map that renders its background and never draws a tile.
- Style-scoped work waits for `style.load`, not `load`. The latter also waits
  for a first complete render, which never arrives if a tile request hangs.
- Definitions are matched to their map by `data-hm-map`, and disposal is decided
  by the container's id rather than `isConnected`, because Hologram morphs the
  old page's DOM into the new one on navigation rather than replacing it.

### Requirements

- Elixir 1.19+, OTP 28.1+, Hologram 0.11+
- MapLibre GL JS 6.x, installed and served by the host application
