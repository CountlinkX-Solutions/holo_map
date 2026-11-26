# Architecture

Why `HoloMap` is built the way it is, and what that costs you.

## The problem

A map library needs three hooks from its framework:

1. **Mount**: build a `maplibregl.Map` once the container is in the DOM.
2. **Update**: push every prop change into that long-lived object.
3. **Unmount**: call `map.remove()` and release the WebGL context.

Hologram 0.11 offers one and a half. `init/2` and `init/3` run once per
component instance, and `put_action/2` can schedule client-side work from there
which covers mount. There is no "props changed" hook and no unmount hook. And
JavaScript interop runs **only inside action handlers**: it is a no-op during
server-side rendering and inside `init` itself.

An imperative design would therefore need every component to fire an action on
every render just to check whether anything changed. That is both impossible
(there is no such hook) and wrong (it would fight the virtual DOM).

## The approach

`HoloMap` does not drive MapLibre from Elixir call sites at all. Every child
component renders **one hidden element carrying its MapLibre specification as
JSON**, and a reconciler in the browser watches those elements:

```
   <HoloMap.Layer.Fill id="parcels-fill" paint={%{fill_color: @colour}} />
                    │
                    │  Hologram renders, and re-renders, this
                    ▼
   <div data-hm="layer"
        data-hm-key="parcels-fill"
        data-hm-map="explorer"
        data-hm-spec='{"type":"fill","paint":{"fill-color":"#3b82f6"}}'
        data-hm-events='{"click":{"action":"parcel_clicked","target":"page","params":{}}}'>
                    │
                    │  MutationObserver sees the attribute change
                    ▼
   map.setPaintProperty("parcels-fill", "fill-color", "#ef4444")
```

Mount, update and unmount all fall out of that:

| Event | What the reconciler does |
| ----- | ------------------------ |
| An element appears | Add the source / layer / marker / control |
| `data-hm-spec` changes | Apply the narrowest MapLibre call that covers the difference |
| `data-hm-events` changes | Rebind listeners |
| An element disappears | Remove the corresponding object |
| The container goes stale | `map.remove()` |

Crucially, this works *with* Hologram's virtual DOM rather than against it.
Hologram already preserves JavaScript-managed children of an element that stays
in the template, which is exactly what MapLibre's canvas is.

## Where the pieces live

```
lib/holo_map/
├── json.ex          A JSON encoder that survives compilation to JavaScript
├── spec.ex          Props → MapLibre specification keys
├── event.ex         Event-handler props → dispatch descriptors
├── def.ex           The shared body of every definition component
├── map.ex           The container; the only stateful component
├── source/          What data comes from
├── layer/           How it looks
├── marker.ex        DOM overlays
├── popup.ex
├── control/         MapLibre's built-in controls
├── terrain.ex       Map-level 3D properties
├── sky.ex
├── api.ex           The imperative escape hatch
├── runtime.ex       The only module that touches JavaScript
└── js/runtime.mjs   The reconciler
```

The shape is deliberate: everything except `runtime.ex` and `runtime.mjs` is
pure Elixir that builds JSON. Since Hologram's interop cannot be reached from
ExUnit, keeping the JavaScript surface to four functions is what makes the rest
of the library testable at all.

## The DOM protocol

| Attribute | Meaning |
| --------- | ------- |
| `data-hm` | Kind: `map`, `source`, `layer`, `marker`, `popup`, `control`, `terrain`, `sky` |
| `data-hm-key` | Identity, unique among definitions of the same kind: a source and a layer may share one. Stable across re-renders; changing it is a remove plus an add |
| `data-hm-map` | The cid of the owning map |
| `data-hm-spec` | The MapLibre specification, JSON-encoded |
| `data-hm-events` | Event name → dispatch descriptor, JSON-encoded |

Definitions render inside `#hm--<cid>--defs`, a hidden sibling of the canvas
container. MapLibre owns `#hm--<cid>`; Hologram owns the defs. Keeping them
apart means MapLibre's DOM and Hologram's DOM never contend for the same node.

## Readiness

MapLibre will not accept `addSource` or `addLayer` before it has parsed a style,
and a page renders its whole component tree before the first byte of style
arrives. So style-scoped work (sources, layers, terrain, sky) is queued and
flushed on **`style.load`**.

Not on `load`. MapLibre's `load` event also waits for the first complete render,
which never arrives if a tile request hangs; gating on it produced a map that
rendered its background and stayed permanently empty.

Markers, popups and controls wait for nothing. They attach to the map object,
not to the style, and queueing them would mean controls that never appear when a
tile server is slow.

## Update costs

Not every prop change costs the same. In rough order:

| Change | Cost |
| ------ | ---- |
| A paint or layout property | `setPaintProperty` / `setLayoutProperty`. Free |
| A layer filter | `setFilter`. Free |
| A layer zoom range | `setLayerZoomRange`. Free |
| A layer's `before_id` | `moveLayer`. Free |
| A GeoJSON source's `data` | `setData`. Free; no layer is disturbed |
| An image source's `url` or `coordinates` | `updateImage`. Free |
| The map's `center` / `zoom` / `bearing` / `pitch` | `jumpTo`. Free |
| A layer's `type`, `source` or `source_layer` | Remove and re-add the layer, at its place |
| Any other source key | Detach the dependent layers, rebuild the source, re-add them at their places |
| The map's `style` | Everything is discarded and re-declared on the next `style.load` |
| A control's props | Remove and re-add the control, at its place in its corner |

The practical guidance: put frequently-changing data in a GeoJSON source's
`data` prop and frequently-changing appearance in `paint`. Both are free.

## Two consequences of DOM morphing

Hologram does **not** tear the old page's DOM down and build the new one on
client-side navigation. It *morphs* one into the other, patching attributes in
place. Any library reconciling DOM state against a long-lived JavaScript object
has to account for that, and `HoloMap` learned both the hard way.

**Definitions must be matched by ownership, not containment.** During a
navigation the outgoing map's definition elements briefly carry the incoming
page's values. A reconciler trusting containment reads that as prop changes on a
live map, moving its camera and dispatching the resulting `moveend` through
`Hologram.dispatchAction`, which is deferred and therefore lands on whichever
page is mounted by then. That surfaced as `FunctionClauseError` in the
*destination* page's `action/3`. Hence `data-hm-map`, and hence camera moves the
reconciler initiates carrying an event marker so they are never reported back.

**Staleness is not `isConnected`.** The outgoing container is patched into the
incoming one rather than removed, so it never stops being connected to the
document. Disposal keyed on `isConnected` alone leaked one WebGL context per
navigation, against a browser limit of roughly sixteen. Staleness is decided by
the container's `id` as well.

## Testing

Three suites, because the library has two halves and only one of them runs on
the BEAM:

- `mix test` covers everything that builds JSON. Component tests render through
  Hologram's own renderer and assert on the attributes each component emits.
- `test/js/` unit-tests `runtime.mjs` with Node's own test runner, against a
  fake `maplibre-gl` and a minimal DOM, both in `test/js/support/`. The tests
  change definition attributes the way Hologram does and assert on what the
  reconciler asked MapLibre for: which call a prop change becomes, what waits
  for `style.load`, what a style swap declares again. They need Node.js 22.15 or
  later and nothing else, so no npm install, browser or network:

  ```console
  $ node --test "test/js/**/*.test.mjs"
  ```

- `demo/test/browser/` drives a real MapLibre instance through Playwright and
  asserts on what MapLibre actually built, through `getLayer`,
  `getPaintProperty` and `getFilter`, reached via `window.HoloMap.map/1`.

The split is forced: Hologram's JS interop is a no-op on the server, so no
amount of ExUnit reaches `runtime.mjs`. The unit tests run on every push to
`main` and on every pull request; only the browser suite shows that MapLibre
accepts what the reconciler hands it. Both navigation bugs above were found by
the browser suite and are pinned there.
