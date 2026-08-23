// WCAG 2 A/AA audit of every page in both colour schemes.
//
// Contrast in particular is not something to eyeball or to compute by hand:
// Tailwind v4 emits oklch(), which a naive luminance calculation parses into
// nonsense. axe-core resolves the actual painted colours.

import { chromium } from "playwright";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const axePath = require.resolve("axe-core");
import { readFileSync } from "fs";
const axeSource = readFileSync(axePath, "utf8");

const BASE = process.env.HOLO_MAP_DEMO_URL || "http://localhost:4000";
let failures = 0;

const browser = await chromium.launch();
for (const scheme of ["light", "dark"]) {
  for (const route of ["/", "/basic", "/geojson", "/vector", "/raster", "/heatmap", "/clustering", "/markers", "/terrain", "/extrusion", "/camera"]) {
    const page = await browser.newPage({ viewport: { width: 1440, height: 950 }, colorScheme: scheme });
    await page.goto(BASE + route, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(route === "/" ? 2000 : 6000);
    await page.addScriptTag({ content: axeSource });
    const res = await page.evaluate(async () => await window.axe.run(document, {
      runOnly: { type: "tag", values: ["wcag2a", "wcag2aa"] },
    }));
    const v = res.violations.map(x => `${x.id}(${x.nodes.length})`);
    if (v.length) failures += 1;
    console.log(`${scheme.padEnd(5)} ${route.padEnd(11)} ${v.length ? "FAIL  " + v.join(", ") : "pass"}`);
    for (const x of res.violations) {
      for (const n of x.nodes.slice(0, 2)) {
        console.log(`        ${x.id}: ${(n.failureSummary || "").split("\n").filter(Boolean).slice(-1)[0]?.trim().slice(0,140)}`);
      }
    }
    await page.close();
  }
}
await browser.close();
console.log(failures ? `\n${failures} page/theme combinations have WCAG violations` : "\nall pages pass WCAG 2 AA in both themes");
process.exit(failures ? 1 : 0);
