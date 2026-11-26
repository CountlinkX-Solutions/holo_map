# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `HoloMap.Marker`'s `on_click`, `on_drag_start`, `on_drag` and `on_drag_end`
  stopped firing once a change to the slot content, `color`, `scale` or
  `class_name` replaced the MapLibre marker. The listeners are now bound to the
  new marker and taken off the old one.
- `HoloMap.Popup`'s `on_open` never fired: MapLibre emits `open` while the popup
  is being added, and the listener was attached afterwards. It now fires when
  the popup first renders and when a changed declaration reopens a popup
  MapLibre had closed.
- Most `HoloMap.Marker` and `HoloMap.Popup` props were read only when the
  MapLibre object was built, so changing them from state did nothing. A
  marker's `opacity`, `pitch_alignment`, `rotation_alignment`,
  `subpixel_positioning`, `popup_html` and `popup_options`, and a popup's
  `max_width`, `offset`, `class_name` and `subpixel_positioning`, now go through
  MapLibre's setters. Options MapLibre has no setter for replace the object: a
  marker's `anchor` and `click_tolerance`, and a popup's `anchor`,
  `close_button`, `close_on_click`, `close_on_move` and `focus_after_open`. A
  popup replaced this way reports neither `on_close` nor `on_open`, and a
  marker's popup that was open stays open when its options change.
- `HoloMap.Marker`'s `popup_options` reached MapLibre with its keys untouched,
  so the documented `HoloMap.Popup` vocabulary (`close_button`, `max_width` and
  the rest) was ignored. Those keys are now converted, with the same boolean
  coercion `HoloMap.Popup` applies; string keys still pass through unchanged.
  An option set to `nil` is left out whatever its key, as everywhere else.
- Clicking a `HoloMap.Marker` that has `on_click` neither opened its
  `popup_html` popup nor closed popups with `close_on_click`. The runtime
  stopped the DOM click so the map's `on_click` would not also fire, but
  MapLibre makes the map's own click from that same DOM event, and handles
  marker popups and `close_on_click` from it. The click is now marked instead
  of stopped: MapLibre sees it, while the map's and layers' `on_click` still
  ignore a click on a marker that reports its own. The DOM click now bubbles
  past the map like any other click on it. The marker's `on_click` is
  dispatched once the click has finished propagating, after the `on_close` of
  any popup it closed, so a popup whose `on_close` clears the selection no
  longer undoes the selection made by clicking another marker.
- A source, a layer and a `HoloMap.Image` that shared an `id`, as a source and
  the layer drawing it often do, replaced one another on every render, leaving
  the map without the source or the layer. The same happened to a layer called
  `terrain` or `sky` next to `HoloMap.Terrain` or `HoloMap.Sky`. Definitions are
  now told apart by kind as well as `id`, and MapLibre still receives the `id`
  unchanged. This also fixes a definition that changed from a source or layer
  to a marker, popup or control before the style had loaded: its new object
  lost its events, and removing the definition left it on the map.
- A layer whose source did not exist yet was handed to MapLibre anyway, which
  refused it with a "source not found" error, and nothing added it later: a
  layer written above its source, a layer rendered while its source was not,
  and the layers of a source that was removed and rendered again all stayed
  missing. Such a layer now waits for its source and is added, in declared
  order, as soon as the source is.
- Layers and controls kept their declared order only on first load. A layer
  rendered conditionally, re-added because its `type`, `source` or
  `source_layer` changed, or re-added by a structural source change went on top
  of every other layer; a changed `before_id` was ignored; and a `before_id`
  naming a layer declared further down, or not rendered yet, was dropped for
  good. Each layer is now placed where the template puts it, a `before_id`
  change moves the layer, and a `before_id` takes effect once the layer it
  names is on the map. A control rendered conditionally, or replaced by a prop
  change, went to the far end of its corner; it now goes back to its declared
  place, and the controls around it are left as they are.
- An inline `style` map was set again on every change to any `HoloMap.Map`
  prop, such as `zoom`, and MapLibre's diff then took every source and layer
  off the map and back on. It is now compared by value. A style change, from
  the prop or `HoloMap.API.set_style/2`, now always builds the new style from
  scratch instead of diffing it, so it always ends in the re-declaration of the
  map's sources, layers, images, terrain and sky; work and `HoloMap.API` calls
  issued while the new style loads wait for it instead of reaching the old
  style or failing with "Style is not done loading". When the new style
  already defines a source of the same `id`, the layers drawing from it are no
  longer added to the style's source, where a vector source refused each one
  with an error; the warning now names them. A style change also no longer
  warns that the new style defines each of the map's own layers.
- Terrain stayed bound to its `HoloMap.Source.RasterDEM` after a change to the
  source's `tiles`, `url`, `encoding` or other structural keys rebuilt it, and
  after the source was removed, so it went on drawing from a source that was no
  longer on the map. It now comes off before the source and goes back on the
  rebuilt one, whether `HoloMap.Terrain` or the terrain control turned it on.
  Removing the source turns terrain off with a warning until the source is
  rendered again. `HoloMap.Terrain` declared above its source, or rendered
  while the source was not, made MapLibre throw "cannot load terrain" and was
  never applied; it now waits for its source, as layers do.
- A `HoloMap.API` call made before its map had booted was dropped with a
  console warning. Hologram runs the actions scheduled from `init` in the order
  of the components' cids, so the documented pattern of moving the camera from
  a page's `init` action lost the call whenever the map's cid sorts after
  `"page"`. Such calls are now queued and run in order once the map's style has
  loaded; calls for a map that has not booted within five seconds are dropped
  with a warning.
- `HoloMap.Map`'s `on_error` received the camera but not the error. Its payload
  now also has an `error` map with the `message`, plus the HTTP `status` and
  `url` of a failed request and the `source_id` of a source's error when
  MapLibre reports them. Only plain values cross into Elixir.
- `HoloMap.Image` applied whichever image load finished last: a slow response
  for an earlier `url` replaced the image of a later one, and a response for an
  image removed while it loaded registered it again, with no component left to
  remove it. A load is now applied only if it is the latest one for an image
  that is still declared.
- Booting a map retried every animation frame for as long as its container was
  missing, for the rest of the page's life if the page moved on first, and
  built the map with no options, so with no style ever, when the map definition
  still named another map during a navigation. Boot now waits a frame at a
  time for both the container and a definition that names the map, and gives
  up with a warning after 60 frames.
- A `HoloMap.Marker`'s `popup_html` popup that the user had opened closed
  whenever a change to the slot content, `color`, `scale`, `class_name`,
  `anchor` or `click_tolerance` replaced the MapLibre marker, so a marker whose
  content follows state closed its own popup on every change. It is now opened
  again on the new marker; a popup the user had not opened stays closed.
- Removing `offset` from a `HoloMap.Marker` drawn as MapLibre's default pin set
  its offset to `[0, 0]`, which moved the tip of the pin off its coordinate.
  It now goes back to MapLibre's own offset for the pin, `[0, -14]`; a marker
  with slot content still goes back to `[0, 0]`.
- A `class_name` with a leading, trailing or repeated space kept a
  `HoloMap.Marker` or `HoloMap.Popup` off the map, and a `popup_options` one
  kept the marker's popup from opening: MapLibre splits it on single spaces and
  the browser refuses the empty class name between two of them. The names now
  reach MapLibre separated by single spaces.
- Every change to an open `HoloMap.Popup` rewrote its content, even a change to
  `lng_lat` alone, so a popup following a moving feature lost its scroll
  position and text selection on every move and, with `focus_after_open`, took
  keyboard focus back. The content is now rewritten only when `html` or the
  slot content changes what the popup shows.

## [0.1.0] - 2026-08-23

### Added

- `HoloMap.Map`, the map container. Stateful, keyed by its Hologram `cid`, which
  is also the DOM container id and the handle for every `HoloMap.API` call.
- Sources: `HoloMap.Source.GeoJSON`, `.Vector`, `.Raster`, `.RasterDEM`,
  `.Image`.
- Layers: `HoloMap.Layer.Fill`, `.Line`, `.Circle`, `.Symbol`, `.Raster`,
  `.Heatmap`, `.Hillshade`, `.FillExtrusion`, plus a generic `HoloMap.Layer`
  for a type decided at runtime.
- Overlays: `HoloMap.Marker` and `HoloMap.Popup`, both accepting slot content.
- `HoloMap.Image`, which registers an image so a symbol layer's `icon_image`,
  or a fill or line layer's pattern, can name it. Without it, only icons the
  style's own sprite carries are reachable, and naming anything else fails
  silently: MapLibre emits `styleimagemissing` and draws nothing.
- Controls: `HoloMap.Control.Navigation`, `.Scale`, `.Geolocate`, `.Fullscreen`,
  `.Attribution`, plus `.Globe` and `.Terrain`, both new in MapLibre GL JS 6.
- 3D: `HoloMap.Terrain` and `HoloMap.Sky`.
- `HoloMap.API`: `fly_to/2`, `ease_to/2`, `jump_to/2`, `fit_bounds/3`,
  `resize/1`, `set_style/2`, `set_filter/3`, `set_paint_property/4`,
  `set_layout_property/4`, `set_feature_state/3`, `remove_feature_state/3`.
- MapLibre events surfaced as Hologram actions, with payloads documented per
  component and in the Events guide.
- `window.HoloMap.map/1`, so MapLibre plugins can reach the raw instance.
- A Phoenix + Hologram demo application exercising every component across
  eleven pages, and Playwright suites driving a real MapLibre instance:
  component behaviour, full source/layer coverage, and navigation.

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

### Behaviour worth knowing

- A popup MapLibre closed on its own (the close button, a click on the map, a
  camera move) left the reconciler believing it was still open. Clicking the
  same feature again changed no state, re-rendered nothing, and the popup never
  returned. `HoloMap.Popup` now reports `on_close` (and `on_open`), a changed
  declaration re-asserts a popup MapLibre had closed, and `addPopup` removes any
  existing instance first so no path can stack two on one coordinate.

- `HoloMap.Sky` cleared itself with `setSky(null)`, which MapLibre validates and
  rejects with "sky: object expected, null found". The sky was cleared anyway,
  but a console error was logged every time the component was removed.
- The documented shape of layer event payloads was wrong. Hologram converts
  JavaScript object keys to atoms **recursively**, so a feature's properties
  arrive as `%{parcel_id: id}`, not `%{"parcel_id" => id}`. Matching with string
  keys silently fails rather than raising, which is why it survived until every
  component was exercised in a browser.

### Requirements

- Elixir 1.19+, OTP 28.1+, Hologram 0.11+
- MapLibre GL JS 6.x, installed and served by the host application

[Unreleased]: https://github.com/CountlinkX-Solutions/holo_map/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/CountlinkX-Solutions/holo_map/releases/tag/v0.1.0
