import { chromium } from "playwright";

const BASE = process.env.HOLO_MAP_DEMO_URL || "http://localhost:4000";
const results = [];
let failures = 0;

function record(name, ok, detail = "") {
  results.push(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? " — " + detail : ""}`);
  if (!ok) failures++;
}

async function step(name, fn) {
  try {
    await fn();
  } catch (error) {
    record(name, false, String(error.message).split(String.fromCharCode(10))[0]);
  }
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

const consoleErrors = [];
page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
page.on("pageerror", (e) => consoleErrors.push("pageerror: " + e.message));

// Report what MapLibre actually built, read from the live map instance.
async function mapReport(cid) {
  return page.evaluate(async (cid) => {
    const el = document.getElementById(`hm--${cid}`);
    if (!el) return { error: "no container" };
    // The canvas MapLibre injects is the proof the instance exists and rendered.
    const canvas = el.querySelector("canvas.maplibregl-canvas");
    return {
      hasCanvas: Boolean(canvas),
      canvasSize: canvas ? [canvas.clientWidth, canvas.clientHeight] : null,
      controls: el.querySelectorAll(".maplibregl-ctrl").length,
      markers: document.querySelectorAll(".maplibregl-marker").length,
      popups: document.querySelectorAll(".maplibregl-popup").length,
    };
  }, cid);
}

async function waitForMap(cid, ms = 20000) {
  await page.waitForFunction(
    (cid) => {
      const el = document.getElementById(`hm--${cid}`);
      return el && el.querySelector("canvas.maplibregl-canvas");
    },
    cid,
    { timeout: ms },
  );
}

// --- basic page: map boots, controls attach, state drives the camera --------
await page.goto(`${BASE}/basic`, { waitUntil: "domcontentloaded" });
await waitForMap("basic");
let r = await mapReport("basic");
record("basic: MapLibre canvas exists", r.hasCanvas);
record("basic: canvas has non-zero size", r.canvasSize && r.canvasSize[0] > 100 && r.canvasSize[1] > 100,
  JSON.stringify(r.canvasSize));
record("basic: three controls attached", r.controls >= 3, `found ${r.controls}`);
record("basic: the map is reachable from plain JavaScript",
  await page.evaluate(() => Boolean(window.HoloMap && window.HoloMap.map("basic"))));

// --- geojson page: source + layers reach MapLibre ----------------------------
await page.goto(`${BASE}/geojson`, { waitUntil: "domcontentloaded" });
await waitForMap("cities");
await page.waitForTimeout(2500);

// Assert on what MapLibre actually built, not on what the DOM looks like.
const layerState = await page.evaluate(() => {
  const map = window.HoloMap.map("cities");
  const style = map.getStyle();
  return {
    hasSource: Boolean(map.getSource("cities")),
    layers: ["cities-circles", "cities-labels"].filter((id) => Boolean(map.getLayer(id))),
    circleColour: map.getPaintProperty("cities-circles", "circle-color"),
    filter: map.getFilter("cities-circles") || null,
    styleLayerCount: style.layers.length,
  };
});
record("geojson: the source reached MapLibre", layerState.hasSource);
record("geojson: both layers reached MapLibre", layerState.layers.length === 2,
  layerState.layers.join(", "));
record("geojson: paint arrived dasherized", layerState.circleColour === "#2563eb",
  String(layerState.circleColour));
record("geojson: no filter while the region is \"all\"", layerState.filter === null,
  JSON.stringify(layerState.filter));

// Changing paint state must not rebuild anything — the canvas node stays put.
const canvasBefore = await page.evaluate(() =>
  document.querySelector("#hm--cities canvas.maplibregl-canvas").getAttribute("width"));
await page.getByRole("button", { name: "Red" }).click();
await page.waitForTimeout(800);
const canvasAfter = await page.evaluate(() =>
  document.querySelector("#hm--cities canvas.maplibregl-canvas").getAttribute("width"));
record("geojson: paint change kept the same canvas", canvasBefore === canvasAfter);
record("geojson: paint change reached the live layer",
  (await page.evaluate(() => window.HoloMap.map("cities").getPaintProperty("cities-circles", "circle-color"))) === "#dc2626");

await page.getByRole("button", { name: "Andes" }).click();
await page.waitForTimeout(800);
record("geojson: filter change reached the live layer",
  JSON.stringify(await page.evaluate(() => window.HoloMap.map("cities").getFilter("cities-circles")))
    === JSON.stringify(["==", ["get", "region"], "andes"]));
record("geojson: nothing errored", consoleErrors.length === 0, consoleErrors.slice(0, 2).join(" | "));

// --- markers page: markers, custom slot content, popup from state -----------
await page.goto(`${BASE}/markers`, { waitUntil: "domcontentloaded" });
await waitForMap("markers");
await page.waitForTimeout(1500);
r = await mapReport("markers");
record("markers: three markers on the map", r.markers === 3, `found ${r.markers}`);
record("markers: custom slot markup was cloned into a marker",
  await page.locator(".maplibregl-marker .chip").count() === 1);

await step("markers: clicking a marker opened a state-driven popup", async () => {
  await page.locator(".maplibregl-marker .chip").click({ timeout: 5000 });
  await page.waitForTimeout(900);
  const rr = await mapReport("markers");
  record("markers: clicking a marker opened a state-driven popup", rr.popups === 1, `found ${rr.popups}`);
});


// The popup's lifecycle against MapLibre closing it on its own.
//
// MapLibre closes a popup for reasons this runtime never hears about — the
// close button, a click on the map, a camera move. Left unreported, the
// component that opened it still believes it is open, so clicking the same
// thing again changes no state, re-renders nothing, and the popup never comes
// back. `on_close` is what keeps the declaration and the screen in agreement.
const popupCount = () => page.evaluate(() => document.querySelectorAll(".maplibregl-popup").length);

await page.locator(".maplibregl-popup-close-button").first().click();
await page.waitForTimeout(1200);
record("popup: the close button removed it", (await popupCount()) === 0);
record("popup: on_close cleared the state that opened it",
  (await page.evaluate(() => document.querySelectorAll('[data-hm="popup"]').length)) === 0);

await page.locator(".maplibregl-marker .chip").click();
await page.waitForTimeout(1200);
record("popup: clicking the same marker opens it again", (await popupCount()) === 1);

// Any path reaching addPopup twice would stack two identical popups on one
// coordinate, which is invisible in the count of anything except popups.
let mostPopups = 0;
for (const act of [
  () => page.locator(".maplibregl-marker .chip").click(),
  () => page.locator(".maplibregl-marker .chip").dblclick(),
  async () => { await page.locator(".maplibregl-marker svg").first().click({ force: true });
                await page.locator(".maplibregl-marker .chip").click(); },
]) {
  await act();
  await page.waitForTimeout(1300);
  mostPopups = Math.max(mostPopups, await popupCount());
}
record("popup: repeated and overlapping opens never stack two", mostPopups === 1, `saw ${mostPopups}`);

// Dragging, with all three handlers live and on_drag writing the position back
// into state on every frame — which means a re-render and a setLngLat back into
// the marker MapLibre is currently dragging. The gap between marker and cursor
// is what would show that fight.
const dragStart = await page.evaluate(() => {
  const rect = document.querySelector(".maplibregl-marker-draggable").getBoundingClientRect();
  return { x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2) };
});

await page.mouse.move(dragStart.x, dragStart.y);
await page.mouse.down();

const dragGaps = [];
for (let i = 1; i <= 10; i++) {
  const cx = dragStart.x + i * 12;
  const cy = dragStart.y + i * 5;
  await page.mouse.move(cx, cy);
  await page.waitForTimeout(70);
  const rect = await page.evaluate(() =>
    document.querySelector(".maplibregl-marker-draggable").getBoundingClientRect());
  dragGaps.push(Math.round(Math.hypot(rect.left + rect.width / 2 - cx, rect.top + rect.height / 2 - cy)));
}

await page.mouse.up();
await page.waitForTimeout(1500);

const dragText = await page.locator(".controls span").first().innerText();
record("markers: on_drag fired on every move", /[1-9]\d* drag events/.test(dragText), dragText);
record("markers: on_drag_start and on_drag_end bracketed it", dragText.includes("idle"), dragText);
record("markers: the marker tracked the cursor exactly while state was rewritten",
  Math.max(...dragGaps) === 0, `max gap ${Math.max(...dragGaps)}px`);
record("markers: the dragged position reached component state",
  !dragText.includes("-69.93, 18.48"), dragText);

// --- clustering: a structural source change survives ------------------------
await page.goto(`${BASE}/clustering`, { waitUntil: "domcontentloaded" });
await waitForMap("clusters");
await page.waitForTimeout(2500);
const before = consoleErrors.length;
await page.getByRole("button", { name: "Radius 90" }).click();
await page.waitForTimeout(1500);
record("clustering: cluster radius change rebuilt the source cleanly",
  consoleErrors.length === before, consoleErrors.slice(before, before + 2).join(" | "));
record("clustering: map still rendering after the rebuild", (await mapReport("clusters")).hasCanvas);
const clusterState = await page.evaluate(() => {
  const map = window.HoloMap.map("clusters");
  return {
    layers: ["cluster-circles", "cluster-counts", "single-points"].filter((id) => Boolean(map.getLayer(id))),
    radius: map.getStyle().sources.points.clusterRadius,
  };
});
record("clustering: all three layers were re-added after the source rebuild",
  clusterState.layers.length === 3, clusterState.layers.join(", "));
record("clustering: the new cluster radius reached the source", clusterState.radius === 90,
  String(clusterState.radius));

// --- camera: the imperative API reaches MapLibre ----------------------------
await page.goto(`${BASE}/camera`, { waitUntil: "domcontentloaded" });
await waitForMap("camera");
await page.waitForTimeout(1500);
await page.getByRole("button", { name: "Kyoto" }).click();
await page.waitForTimeout(3000);
const flew = await page.locator(".controls span").first().innerText();
record("camera: fly_to ran and the action updated state", flew.includes("Kyoto"), flew);

// --- teardown: navigating away must dispose the WebGL context ---------------
await page.goto(`${BASE}/basic`, { waitUntil: "domcontentloaded" });
await waitForMap("basic");
await page.waitForTimeout(1000);
await page.getByRole("link", { name: "Index" }).click();
await page.waitForTimeout(1500);
const leaked = await page.evaluate(() => document.querySelectorAll("canvas.maplibregl-canvas").length);
record("teardown: leaving the page removed the map canvas", leaked === 0, `${leaked} left`);
record("teardown: the map was unregistered, not just hidden",
  (await page.evaluate(() => window.HoloMap.cids().length)) === 0);

await page.screenshot({ path: process.env.SHOT || "shot.png", fullPage: false });

await browser.close();

console.log(results.join("\n"));
console.log(`\n${results.length - failures}/${results.length} checks passed`);
if (consoleErrors.length) {
  console.log("\nconsole errors:\n" + consoleErrors.slice(0, 8).join("\n"));
}
process.exit(failures ? 1 : 0);
