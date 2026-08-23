import { chromium } from "playwright";

// Regression test for: navigating away from a map page raised
// FunctionClauseError on the *destination* page, because the old map kept
// emitting `moveend` and dispatching :camera_moved at "page".
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

const errors = [];
page.on("pageerror", (e) => errors.push(e.message.split("\n").find((l) => l.trim()) || e.message));
page.on("console", (m) => { const t = m.text(); if (m.type() === "error" && !t.includes("GL Driver")) errors.push("console: " + t.slice(0, 200)); });

const BASE = process.env.HOLO_MAP_DEMO_URL || "http://localhost:4000";
await page.goto(BASE + "/", { waitUntil: "domcontentloaded" });

// Click through the nav the way a person does, several times, pausing long
// enough for tiles to start and for a camera event to be in flight.
const links = ["Basic", "GeoJSON", "Markers", "Clustering", "Camera", "Basic", "GeoJSON", "Index", "Basic", "Camera", "GeoJSON"];

for (const name of links) {
  await page.getByRole("link", { name, exact: true }).click();
  await page.waitForTimeout(1800);
}

// And the reported path specifically: interact with the basic map first, so a
// camera event is genuinely pending when the navigation happens.
await page.getByRole("link", { name: "Basic", exact: true }).click();
await page.waitForTimeout(2500);
await page.locator(".controls button", { hasText: "Toggle tilt" }).click();
await page.getByRole("link", { name: "GeoJSON", exact: true }).click();
await page.waitForTimeout(2500);

const live = await page.evaluate(() => window.HoloMap.cids());
const canvases = await page.evaluate(() => document.querySelectorAll("canvas.maplibregl-canvas").length);

console.log("live maps after 13 navigations: " + JSON.stringify(live));
console.log("canvases in the document: " + canvases);
console.log("errors: " + errors.length);
errors.slice(0, 6).forEach((e) => console.log("  " + e.slice(0, 220)));

await browser.close();
process.exit(errors.length === 0 && live.length === 1 && canvases === 1 ? 0 : 1);
