// Covers the components that unit tests cannot reach.
//
// A unit test asserts that `min_zoom` becomes `"minzoom"` — the key this
// library chose. Nothing there proves MapLibre *accepts* that key. Only a
// browser does, so every source and layer type gets exercised against a real
// map here, against data published by MapLibre's own documentation.

import { chromium } from "playwright";

const BASE = process.env.HOLO_MAP_DEMO_URL || "http://localhost:4000";
const results = [];
let failures = 0;

function record(name, ok, detail = "") {
  results.push(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
  if (!ok) failures++;
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

const errors = [];
page.on("pageerror", (e) => errors.push(e.message.split(String.fromCharCode(10))[0]));
page.on("console", (m) => {
  const t = m.text();
  if (m.type() === "error" && !t.includes("GL Driver") && !t.includes("Failed to load resource"))
    errors.push("console: " + t.slice(0, 160));
});

async function open(route, cid) {
  await page.goto(BASE + route, { waitUntil: "domcontentloaded" });
  await page.waitForFunction((c) => window.HoloMap && window.HoloMap.map(c), cid, { timeout: 25000 });
  // Wait for the style to parse, which is when sources and layers land.
  await page.waitForFunction((c) => window.HoloMap.map(c).isStyleLoaded(), cid, { timeout: 30000 })
    .catch(() => {});
  await page.waitForTimeout(2500);
}

const inspect = (cid, fn) => page.evaluate(({ cid, body }) => {
  const map = window.HoloMap.map(cid);
  return new Function("map", body)(map);
}, { cid, body: `return (${fn})(map);` });

// --- vector source, fill and line layers, attribution control ---------------
await open("/vector", "vector");
let r = await inspect("vector", (map) => ({
  source: map.getSource("demo")?.type ?? null,
  fill: map.getLayer("countries-fill")?.type ?? null,
  line: map.getLayer("countries-outline")?.type ?? null,
  sourceLayer: map.getStyle().layers.find((l) => l.id === "countries-fill")?.["source-layer"] ?? null,
  lineCap: map.getLayoutProperty("countries-outline", "line-cap"),
}));
record("vector: HoloMap.Source.Vector reached MapLibre", r.source === "vector", String(r.source));
record("vector: HoloMap.Layer.Fill reached MapLibre", r.fill === "fill", String(r.fill));
record("vector: HoloMap.Layer.Line reached MapLibre", r.line === "line", String(r.line));
record("vector: source_layer arrived as \"source-layer\"", r.sourceLayer === "countries", String(r.sourceLayer));
record("vector: layout props dasherized (line_cap)", r.lineCap === "round", String(r.lineCap));
record("vector: HoloMap.Control.Attribution attached",
  (await page.locator(".maplibregl-ctrl-attrib").count()) > 0);

await page.getByRole("button", { name: "Filter to Europe" }).click();
await page.waitForTimeout(900);
record("vector: filter change reached the live layer",
  JSON.stringify(await inspect("vector", (map) => map.getFilter("countries-fill"))) ===
    JSON.stringify(["==", ["get", "REGION_UN"], "Europe"]));

// The imperative API duplicates what props already do, so it needs its own
// coverage: a wrong MapLibre method name is a silent no-op otherwise.
await page.getByRole("button", { name: "Flash amber (imperative)" }).click();
await page.waitForTimeout(700);
record("vector: HoloMap.API.set_paint_property reached the layer",
  (await inspect("vector", (map) => map.getPaintProperty("countries-fill", "fill-color"))) === "#b45309");

await page.getByRole("button", { name: "Hide outline (imperative)" }).click();
await page.waitForTimeout(700);
record("vector: HoloMap.API.set_layout_property reached the layer",
  (await inspect("vector", (map) => map.getLayoutProperty("countries-outline", "visibility"))) === "none");

await page.getByRole("button", { name: "Filter to Asia (imperative)" }).click();
await page.waitForTimeout(700);
record("vector: HoloMap.API.set_filter reached the layer",
  JSON.stringify(await inspect("vector", (map) => map.getFilter("countries-fill")))
    === JSON.stringify(["==", ["get", "REGION_UN"], "Asia"]));

// A style swap wipes every source and layer; the reconciler must put back the
// ones it owns once the new style loads.
await page.getByRole("button", { name: "Swap style (imperative)" }).click();
await page.waitForTimeout(5000);
record("vector: HoloMap.API.set_style replaced the style",
  (await inspect("vector", (map) => map.getStyle().layers.length)) > 3);
record("vector: the reconciler re-declared its own layers after the swap",
  await inspect("vector", (map) =>
    Boolean(map.getSource("demo") && map.getLayer("countries-fill") && map.getLayer("countries-outline"))));

// --- raster source, image source, raster layers -----------------------------
await open("/raster", "raster");
r = await inspect("raster", (map) => {
  const style = map.getStyle();
  return {
    osm: map.getSource("osm")?.type ?? null,
    radar: map.getSource("radar")?.type ?? null,
    osmLayer: map.getLayer("osm-layer")?.type ?? null,
    radarLayer: map.getLayer("radar-layer")?.type ?? null,
    tileSize: style.sources.osm.tileSize,
    radarUrl: style.sources.radar.url,
    coordinates: style.sources.radar.coordinates,
    opacity: map.getPaintProperty("radar-layer", "raster-opacity"),
  };
});
record("raster: HoloMap.Source.Raster reached MapLibre", r.osm === "raster", String(r.osm));
record("raster: tile_size arrived as \"tileSize\"", r.tileSize === 256, String(r.tileSize));
record("raster: HoloMap.Source.Image reached MapLibre", r.radar === "image", String(r.radar));
record("raster: image corners normalised to [lng, lat] pairs",
  Array.isArray(r.coordinates) && r.coordinates.length === 4 && r.coordinates[0].length === 2,
  JSON.stringify(r.coordinates?.[0]));
record("raster: two HoloMap.Layer.Raster reached MapLibre",
  r.osmLayer === "raster" && r.radarLayer === "raster");
record("raster: raster_opacity dasherized", r.opacity === 0.85, String(r.opacity));

const before = r.radarUrl;
await page.getByRole("button", { name: "Next radar frame" }).click();
await page.waitForTimeout(1200);
const after = await inspect("raster", (map) => map.getStyle().sources.radar.url);
record("raster: changing the image url updated the source in place", after !== before, after?.slice(-12));

await page.getByRole("button", { name: "Hide radar" }).click();
await page.waitForTimeout(800);
record("raster: visible={false} became layout visibility none",
  (await inspect("raster", (map) => map.getLayoutProperty("radar-layer", "visibility"))) === "none");

// --- heatmap layer, geolocate control ---------------------------------------
await open("/heatmap", "quakes");
r = await inspect("quakes", (map) => ({
  source: map.getSource("earthquakes")?.type ?? null,
  heat: map.getLayer("earthquakes-heat")?.type ?? null,
  points: map.getLayer("earthquakes-points")?.type ?? null,
  weight: map.getPaintProperty("earthquakes-heat", "heatmap-weight"),
  features: map.querySourceFeatures("earthquakes").length,
}));
record("heatmap: GeoJSON loaded from a URL", r.source === "geojson" && r.features > 0, `${r.features} features`);
record("heatmap: HoloMap.Layer.Heatmap reached MapLibre", r.heat === "heatmap", String(r.heat));
record("heatmap: companion circle layer reached MapLibre", r.points === "circle", String(r.points));
record("heatmap: heatmap_weight expression arrived intact", Array.isArray(r.weight));
record("heatmap: HoloMap.Control.Geolocate attached",
  (await page.locator(".maplibregl-ctrl-geolocate").count()) > 0);

// --- raster-dem source, terrain, hillshade, sky ------------------------------
await open("/terrain", "relief");
r = await inspect("relief", (map) => ({
  dem: map.getSource("dem")?.type ?? null,
  encoding: map.getStyle().sources.dem.encoding,
  terrain: map.getTerrain(),
  hillshade: map.getLayer("relief-shade")?.type ?? null,
  sky: map.getSky(),
  pitch: map.getPitch(),
}));
record("terrain: HoloMap.Source.RasterDEM reached MapLibre", r.dem === "raster-dem", String(r.dem));
record("terrain: encoding passed through", r.encoding === "terrarium", String(r.encoding));
record("terrain: HoloMap.Terrain set the terrain", r.terrain !== null && r.terrain?.source === "dem",
  JSON.stringify(r.terrain));
record("terrain: exaggeration reached MapLibre", r.terrain?.exaggeration === 1.4, String(r.terrain?.exaggeration));
record("terrain: HoloMap.Layer.Hillshade reached MapLibre", r.hillshade === "hillshade", String(r.hillshade));
record("terrain: HoloMap.Sky set the sky", r.sky != null && r.sky["sky-color"] === "#199EF3",
  JSON.stringify(r.sky).slice(0, 60));

await page.getByRole("button", { name: "Hide sky" }).click();
await page.waitForTimeout(900);
record("terrain: removing the Sky component cleared it",
  (await inspect("relief", (map) => map.getSky())) == null);

await page.getByRole("button", { name: "Flat" }).click();
await page.waitForTimeout(900);
record("terrain: flattening the camera left the terrain in place",
  (await inspect("relief", (map) => map.getTerrain() !== null)));

await page.getByRole("button", { name: "Hide hillshade" }).click();
await page.waitForTimeout(900);
record("terrain: removing the Hillshade component removed the layer",
  (await inspect("relief", (map) => map.getLayer("relief-shade") ?? null)) === null);

// --- fill-extrusion, over a basemap, and two maps on one page --------------
await page.goto(BASE + "/extrusion", { waitUntil: "domcontentloaded" });
await page.waitForFunction(
  () => window.HoloMap && window.HoloMap.map("buildings") && window.HoloMap.map("blocks"),
  null,
  { timeout: 30000 },
);
await page.waitForTimeout(9000);

record("extrusion: two maps run side by side on one page",
  (await page.evaluate(() => window.HoloMap.cids().sort().join(","))) === "blocks,buildings");
record("extrusion: each map got its own canvas",
  (await page.evaluate(() => document.querySelectorAll("canvas.maplibregl-canvas").length)) === 2);

r = await inspect("buildings", (map) => {
  const ids = map.getStyle().layers.map((l) => l.id);
  return {
    layer: map.getLayer("osm-buildings")?.type ?? null,
    rendered: map.queryRenderedFeatures({ layers: ["osm-buildings"] }).length,
    beforeLabels: ids.indexOf("osm-buildings") < ids.indexOf("waterway_line_label"),
    height: map.getPaintProperty("osm-buildings", "fill-extrusion-height"),
  };
});
record("extrusion: FillExtrusion on a source the style owns", r.layer === "fill-extrusion", String(r.layer));
record("extrusion: real OpenStreetMap buildings rendered", r.rendered > 100, `${r.rendered} buildings`);
record("extrusion: before_id placed the layer beneath the labels", r.beforeLabels);
record("extrusion: zoom-driven height expression arrived intact", Array.isArray(r.height));

r = await inspect("blocks", (map) => ({
  layer: map.getLayer("blocks-3d")?.type ?? null,
  raster: map.getLayer("osm-base")?.type ?? null,
  rendered: map.queryRenderedFeatures({ layers: ["blocks-3d"] }).length,
  gradient: map.getPaintProperty("blocks-3d", "fill-extrusion-vertical-gradient"),
  height: map.getPaintProperty("blocks-3d", "fill-extrusion-height"),
}));
record("extrusion: FillExtrusion on application-owned GeoJSON", r.layer === "fill-extrusion", String(r.layer));
record("extrusion: it sits over a raster basemap", r.raster === "raster", String(r.raster));
record("extrusion: the application's own polygons rendered", r.rendered > 10, `${r.rendered} blocks`);
record("extrusion: multi-word paint key dasherized correctly", r.gradient === true, String(r.gradient));
record("extrusion: height expression arrived intact",
  JSON.stringify(r.height) === JSON.stringify(["*", ["get", "height"], 1]), JSON.stringify(r.height));

await page.getByRole("button", { name: "×6" }).click();
await page.waitForTimeout(900);
record("extrusion: changing the multiplier reached the live layer",
  JSON.stringify(await inspect("blocks", (map) => map.getPaintProperty("blocks-3d", "fill-extrusion-height")))
    === JSON.stringify(["*", ["get", "height"], 6]));

// --- feature state -----------------------------------------------------------
await open("/geojson", "cities");
const target = await page.evaluate(() => {
  const map = window.HoloMap.map("cities");
  // Santo Domingo, one of the features the page renders.
  const p = map.project([-69.93, 18.48]);
  const rect = document.getElementById("hm--cities").getBoundingClientRect();
  return { x: rect.left + p.x, y: rect.top + p.y };
});

await page.mouse.move(target.x - 30, target.y - 30);
await page.waitForTimeout(200);
await page.mouse.move(target.x, target.y);
await page.waitForTimeout(1500);

const hovered = await inspect("cities", (map) =>
  map.querySourceFeatures("cities").some(
    (f) => map.getFeatureState({ source: "cities", id: f.id })?.hover === true,
  ));

record("geojson: HoloMap.API.set_feature_state marked a hovered feature", hovered,
  hovered ? "" : "no feature carries hover state (pointer may not have crossed one)");

record("no uncaught errors across all pages", errors.length === 0, errors.slice(0, 3).join(" | "));

await browser.close();
console.log(results.join(String.fromCharCode(10)));
console.log(`${results.length - failures}/${results.length} checks passed`);
process.exit(failures ? 1 : 0);
