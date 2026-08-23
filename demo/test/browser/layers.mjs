import { chromium } from "playwright";

// Does every declared layer actually draw something?
//
// This exists because of a bug the other suites could not see: a filter naming
// a property the tiles did not carry. The expression reached the layer exactly
// as written, every assertion passed, and the layer rendered nothing at all.
// Checking that a value arrived is not the same as checking that it did
// anything, and this file asks the second question of every layer on every page.
//
// Two exemptions, both real rather than convenient: raster and hillshade layers
// have no queryable features, so a count says nothing about them; and a layer
// below its own minzoom is meant to be empty.
const PAGES = [
  ["/basic", ["basic"]], ["/geojson", ["cities"]], ["/markers", ["markers", "symbols"]],
  ["/clustering", ["clusters"]], ["/vector", ["vector"]], ["/raster", ["raster"]],
  ["/heatmap", ["quakes"]], ["/terrain", ["relief", "user-relief"]],
  ["/extrusion", ["buildings", "blocks"]], ["/camera", ["camera", "stale"]],
];

const BASE = process.env.HOLO_MAP_DEMO_URL || "http://localhost:4000";
const browser = await chromium.launch();
let empty = 0;
for (const [route, cids] of PAGES) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  await page.goto(BASE + route, { waitUntil: "domcontentloaded" });
  await page.waitForFunction((cs) => cs.every(c => window.HoloMap?.map(c)), cids, { timeout: 30000 });
  await page.waitForTimeout(9000);
  for (const cid of cids) {
    const rows = await page.evaluate((c) => {
      const m = window.HoloMap.map(c);
      // Only the layers this demo declared, not the ones the style brought.
      const owned = Array.from(document.querySelectorAll(`[data-hm="layer"][data-hm-map="${c}"]`))
        .map(e => e.getAttribute("data-hm-key"));
      // queryRenderedFeatures only answers for layers backed by vector data.
      // A raster or hillshade layer has no features to return, so "0 drawn"
      // there means nothing at all.
      const QUERYABLE = ["fill", "line", "circle", "symbol", "heatmap", "fill-extrusion"];
      return owned.map(id => {
        const l = m.getLayer(id);
        if (!l) return { id, type: "MISSING", drawn: 0, note: "layer absent" };
        const spec = m.getStyle().layers.find(x => x.id === id) || {};
        const zoom = m.getZoom();
        const belowMin = spec.minzoom !== undefined && zoom < spec.minzoom;
        if (!QUERYABLE.includes(l.type))
          return { id, type: l.type, drawn: null, note: "not queryable" };
        return { id, type: l.type,
          drawn: m.queryRenderedFeatures({ layers: [id] }).length,
          note: belowMin ? `below minzoom ${spec.minzoom} at z${zoom.toFixed(1)}` : "" };
      });
    }, cid);
    for (const r of rows) {
      const bad = r.drawn === 0 && !r.note;
      if (bad) empty++;
      const d = r.drawn === null ? "n/a " : String(r.drawn).padEnd(4);
      console.log(`${bad ? "EMPTY " : "ok    "} ${route.padEnd(11)} ${r.id.padEnd(18)} ${r.type.padEnd(14)} drawn=${d} ${r.note}`);
    }
  }
  await page.close();
}
await browser.close();
console.log(empty ? `\n${empty} layer(s) reach MapLibre and draw nothing` : "\nevery declared layer draws features");
process.exit(empty ? 1 : 0);
