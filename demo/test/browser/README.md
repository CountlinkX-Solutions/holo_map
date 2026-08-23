# Browser tests

`HoloMap`'s Elixir half is covered by `mix test` in the library. Its browser half
cannot be: Hologram's JavaScript interop is a no-op on the server, so nothing in
`HoloMap.Runtime` or `runtime.mjs` is reachable from ExUnit. These scripts cover
that half against a real MapLibre instance in a real browser.

They assert on **what MapLibre actually built**, through `map.getLayer/1`,
`map.getPaintProperty/2` and `map.getFilter/1`, rather than on what the DOM happens
to look like, reaching the instance through `window.HoloMap.map(cid)`.

## Running

Start the demo in one terminal:

```console
$ cd demo && mix server
```

Then, in another:

```console
$ cd demo/test/browser
$ npm install
$ npx playwright install chromium   # first time only
$ npm test
```

`HOLO_MAP_DEMO_URL` overrides the base URL (default `http://localhost:4000`).

## What each covers

`coverage.mjs` covers every source and layer type, against data published by
MapLibre's own documentation: a vector source with fill and line layers, a
raster source over OpenStreetMap tiles, an image source stepping through radar
frames, a heatmap over six thousand earthquakes, a raster-DEM source driving
terrain and hillshade, a sky, fill-extrusion over both a basemap's own source
and application-owned GeoJSON, two maps on one page, an image registered with `HoloMap.Image` and resolved by
a symbol layer's `icon_image`, every control including
MapLibre 6's globe and terrain buttons, and each of the eleven `HoloMap.API`
functions.

This file exists because a unit test asserts that `min_zoom` becomes
`"minzoom"`, the key *this library chose*. Nothing there proves MapLibre
*accepts* that key. Only a browser does, and every component here is checked
against the live map rather than against the DOM: `map.getSource/1`,
`map.getLayer/1`, `map.getPaintProperty/2`, `map.getTerrain/0`, `map.getSky/0`.

`components.mjs` covers one map booting with a non-zero canvas and its controls; a
GeoJSON source and its layers reaching MapLibre; a paint change arriving as
`setPaintProperty` without rebuilding the canvas; a filter change arriving as
`setFilter`; markers including cloned slot markup; a popup opening from state; a
clustered source surviving a structural rebuild with its three layers re-added;
`HoloMap.API.fly_to/2`; and teardown releasing the WebGL context.

`accessibility.mjs` covers every page in both colour schemes, audited with axe-core
against WCAG 2 A and AA. Contrast is the reason this is a tool and not a
calculation: Tailwind v4 emits `oklch()`, which a hand-written luminance
formula parses into nonsense. Two hand-rolled attempts here produced
contradictory numbers before axe-core gave the real answer.

`navigation.mjs` runs thirteen page transitions in a row, asserting zero
uncaught errors and exactly one live map and one canvas at the end.

That second file exists because of two bugs that only appear when navigating.
Hologram does not tear the old page's DOM down and build the new one, it
*morphs* one into the other. So:

  * The outgoing map's definition elements briefly carry the incoming page's
    values, which the reconciler read as prop changes on the live map, moving
    its camera, and dispatching the resulting `moveend` to whichever page was
    mounted by the time the action ran. `data-hm-map` ownership checks and an
    event marker on reconciler-initiated camera moves fixed it.
  * The outgoing container is patched into the incoming one rather than
    removed, so it never stops being connected to the document, and a liveness
    check built on `isConnected` alone left one WebGL context leaked per
    navigation. Staleness is now decided by the container's id.

Neither is visible on a single page, and both are the sort of thing that only
shows up in a browser.
