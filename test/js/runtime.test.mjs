// Unit tests for lib/holo_map/js/runtime.mjs, the reconciler between
// HoloMap's definition elements and a MapLibre map.
//
// They run under `node --test` against a fake maplibre-gl and a small DOM
// (see support/), with no browser and no network. Each test renders a map's
// definitions, lets the runtime reconcile them, and asserts on what the fake
// map was asked to do and what it now holds. Definitions change the way
// Hologram changes them, through attributes, so updates travel through the
// runtime's own MutationObserver.

import assert from "node:assert/strict";
import { afterEach, describe, test } from "node:test";

import {
  dispatched,
  logged,
  maplibre,
  mountMap,
  nextTask,
  runtime,
  settle,
  unmountAll,
} from "./support/harness.mjs";

const STYLE = "https://tiles.test/style.json";

const point = (name, coordinates) => ({
  type: "Feature",
  properties: { name },
  geometry: { type: "Point", coordinates },
});

const POINTS = {
  type: "FeatureCollection",
  features: [point("Santo Domingo", [-69.9, 18.5])],
};

const MORE_POINTS = {
  type: "FeatureCollection",
  features: [...POINTS.features, point("Santiago", [-70.7, 19.5])],
};

const SOURCE = { kind: "source", key: "cities", spec: { type: "geojson", data: POINTS } };

const CIRCLES = {
  kind: "layer",
  key: "cities-circles",
  spec: {
    type: "circle",
    source: "cities",
    paint: { "circle-radius": 4, "circle-opacity": 0.5 },
  },
};

const LABELS = {
  kind: "layer",
  key: "cities-labels",
  spec: { type: "symbol", source: "cities", layout: { "text-field": ["get", "name"] } },
};

// A map with one GeoJSON source and two layers on it, its style loaded and
// its call log cleared, so a test sees only what its own change caused.
function loadedCitiesMap(extra = []) {
  const handle = mountMap({ defs: [SOURCE, CIRCLES, LABELS, ...extra] });
  handle.map.loadStyle();
  handle.map.calls.length = 0;
  return handle;
}

// The calls among `names`, as [name, id] pairs, in the order they were made.
// addLayer receives a whole layer, so its id is read from it.
function sequence(map, names) {
  return map.calls
    .filter(([name]) => names.includes(name))
    .map(([name, target]) => [name, typeof target === "string" ? target : target.id]);
}

const DRAG_EVENTS = ["dragstart", "drag", "dragend"];

const MARKER_EVENTS = {
  click: { action: "picked", target: "page" },
  dragstart: { action: "drag_started", target: "page" },
  drag: { action: "dragged", target: "page" },
  dragend: { action: "dropped", target: "page" },
};

// Clicks `element` the way the user does, and waits for the task after the
// click, which is where the runtime reports a click on a marker.
async function userClick(element) {
  await element.dispatchUserEvent({ type: "click" });
  await nextTask();
}

// Clicks a marker and plays a drag on it, each the way MapLibre reports it: a
// DOM click on the marker's element, drag events on the marker itself.
async function clickAndDrag(marker) {
  await userClick(marker.getElement());
  DRAG_EVENTS.forEach((name) => marker.fire(name));
}

// A popup whose opening and closing are reported.
const INFO = {
  kind: "popup",
  key: "info",
  spec: { lngLat: [0, 0], html: "<p>One</p>" },
  events: {
    open: { action: "shown", target: "page" },
    close: { action: "closed", target: "page" },
  },
};

// The runtime's listeners still attached to a marker: on its element and on
// the marker as an emitter.
function markerListeners(marker) {
  const element = marker.getElement().listeners.filter(({ name }) => name === "click").length;
  const emitter = DRAG_EVENTS.reduce((count, name) => count + marker.listenerCount(name), 0);

  return element + emitter;
}

afterEach(() => {
  unmountAll();
  dispatched.length = 0;
  logged.warnings.length = 0;

  // runtime.mjs catches whatever a definition throws and logs it, so a test
  // whose work failed would otherwise pass on what it never checked.
  const errors = logged.errors.splice(0);
  assert.deepEqual(errors, [], "the runtime logged errors");
});

describe("boot", () => {
  test("constructs MapLibre from the map definition, with the worker URL set apart", () => {
    const { map, container } = mountMap({
      spec: {
        style: STYLE,
        center: [-69.9, 18.5],
        zoom: 6,
        workerUrl: "/assets/maplibre-gl-worker.mjs",
      },
    });

    assert.deepEqual(map.options, { style: STYLE, center: [-69.9, 18.5], zoom: 6, container });
    assert.equal(maplibre.workerUrl, "/assets/maplibre-gl-worker.mjs");
  });

  test("makes the live map reachable through instance/1", () => {
    const { cid, map } = mountMap();

    assert.equal(runtime.instance(cid), map);
  });
});

describe("add", () => {
  test("queues sources and layers until the style loads, then adds them in template order", () => {
    const { map } = mountMap({ defs: [SOURCE, CIRCLES, LABELS] });

    assert.deepEqual(map.callsTo("addSource"), []);
    assert.deepEqual(map.callsTo("addLayer"), []);

    map.loadStyle();

    assert.deepEqual(sequence(map, ["addSource", "addLayer"]), [
      ["addSource", "cities"],
      ["addLayer", "cities-circles"],
      ["addLayer", "cities-labels"],
    ]);
    assert.deepEqual(map.callsTo("addSource"), [["cities", { type: "geojson", data: POINTS }]]);
    assert.deepEqual(
      map.callsTo("addLayer").map(([layer]) => layer),
      [
        { id: "cities-circles", ...CIRCLES.spec },
        { id: "cities-labels", ...LABELS.spec },
      ],
    );
    assert.deepEqual(map.layerIds(), ["cities-circles", "cities-labels"]);
  });

  test("adds markers and controls without waiting for the style", () => {
    const { map } = mountMap({
      defs: [
        { kind: "marker", key: "office", spec: { lngLat: [-69.9, 18.5], color: "#e11d48" } },
        {
          kind: "control",
          key: "nav",
          spec: { control: "navigation", position: "top-left", showCompass: false },
        },
      ],
    });

    const [marker] = map.markers;
    assert.equal(map.markers.size, 1);
    assert.deepEqual(marker.getLngLat(), { lng: -69.9, lat: 18.5 });
    assert.deepEqual(marker.options, { color: "#e11d48" });

    assert.equal(map.controls.length, 1);
    assert.ok(map.controls[0].control instanceof maplibre.NavigationControl);
    assert.equal(map.controls[0].position, "top-left");
    assert.deepEqual(map.controls[0].control.options, { showCompass: false });
  });

  test("gives a marker a copy of its slot markup, or the default pin for a blank slot", () => {
    const { map, def } = mountMap({
      defs: [
        {
          kind: "marker",
          key: "hq",
          spec: { lngLat: [0, 0], className: "hq" },
          content: '<span class="badge">HQ</span>',
        },
        { kind: "marker", key: "plain", spec: { lngLat: [1, 1] }, content: "\n    " },
      ],
    });

    const [custom, plain] = map.markers;

    assert.equal(custom.options.element.innerHTML, '<span class="badge">HQ</span>');
    assert.equal(custom.options.element.className, "holo-map-marker hq");
    assert.notEqual(custom.options.element, def("hq").children[0]);
    assert.equal(plain.options.element, undefined);
  });

  test("opens a declared popup on the map", () => {
    const { map } = mountMap({
      defs: [
        {
          kind: "popup",
          key: "info",
          spec: { lngLat: [-69.9, 18.5], maxWidth: "240px" },
          content: "<p>Hello</p>",
        },
      ],
    });

    const [popup] = map.popups;
    assert.equal(map.popups.size, 1);
    assert.ok(popup.isOpen());
    assert.deepEqual(popup.lngLat, [-69.9, 18.5]);
    assert.equal(popup.html, "<p>Hello</p>");
    assert.deepEqual(popup.options, { maxWidth: "240px" });
  });

  test("applies a definition that appears after the style loaded straight away", async () => {
    const handle = loadedCitiesMap();
    const regions = { type: "geojson", data: POINTS };

    handle.add({ kind: "source", key: "regions", spec: regions });
    await settle();

    assert.deepEqual(handle.map.callsTo("addSource"), [["regions", regions]]);
  });

  test("runs HoloMap.API calls made before the style loads once it has", () => {
    const { cid, map } = mountMap();

    runtime.invoke(cid, "jumpTo", [{ zoom: 4 }]);
    assert.deepEqual(map.callsTo("jumpTo"), []);

    map.loadStyle();
    assert.deepEqual(map.callsTo("jumpTo"), [[{ zoom: 4 }, {}]]);
  });
});

describe("update", () => {
  test("applies a paint change in place, resetting a dropped property to its default", async () => {
    const handle = loadedCitiesMap();

    handle.setSpec("cities-circles", {
      type: "circle",
      source: "cities",
      paint: { "circle-radius": 8, "circle-color": "#2563eb" },
    });
    await settle();

    const changed = Object.fromEntries(
      handle.map
        .callsTo("setPaintProperty")
        .map(([id, name, value]) => [`${id} ${name}`, value]),
    );

    assert.deepEqual(changed, {
      "cities-circles circle-radius": 8,
      "cities-circles circle-color": "#2563eb",
      "cities-circles circle-opacity": undefined,
    });
    assert.deepEqual(handle.map.callsTo("removeLayer"), []);
    assert.deepEqual(handle.map.callsTo("addLayer"), []);
  });

  test("applies filter, layout and zoom range changes in place", async () => {
    const handle = loadedCitiesMap();
    const filter = ["==", ["get", "name"], "Santiago"];

    handle.setSpec("cities-labels", {
      ...LABELS.spec,
      layout: { "text-field": ["get", "name"], visibility: "none" },
      filter,
      minzoom: 5,
    });
    await settle();

    assert.deepEqual(handle.map.callsTo("setLayoutProperty"), [
      ["cities-labels", "visibility", "none"],
    ]);
    assert.deepEqual(handle.map.callsTo("setFilter"), [["cities-labels", filter]]);
    assert.deepEqual(handle.map.callsTo("setLayerZoomRange"), [["cities-labels", 5, 24]]);

    handle.map.calls.length = 0;
    handle.setSpec("cities-labels", LABELS.spec);
    await settle();

    assert.deepEqual(handle.map.callsTo("setFilter"), [["cities-labels", null]]);
    assert.deepEqual(handle.map.callsTo("addLayer"), []);
  });

  test("replaces a layer whose type changes", async () => {
    const handle = loadedCitiesMap();

    handle.setSpec("cities-circles", { type: "heatmap", source: "cities" });
    await settle();

    assert.deepEqual(sequence(handle.map, ["removeLayer", "addLayer"]), [
      ["removeLayer", "cities-circles"],
      ["addLayer", "cities-circles"],
    ]);
    assert.deepEqual(
      handle.map.callsTo("addLayer").map(([layer]) => layer),
      [{ id: "cities-circles", type: "heatmap", source: "cities" }],
    );
    assert.equal(handle.map.getLayer("cities-circles").type, "heatmap");
  });

  test("hands new GeoJSON data to setData without rebuilding the source", async () => {
    const handle = loadedCitiesMap();

    handle.setSpec("cities", { type: "geojson", data: MORE_POINTS });
    await settle();

    assert.deepEqual(handle.map.callsTo("setData"), [["cities", MORE_POINTS]]);
    assert.deepEqual(handle.map.callsTo("removeSource"), []);
    assert.deepEqual(handle.map.callsTo("removeLayer"), []);
  });

  test("rebuilds a source whose structure changes, with the layers that use it", async () => {
    const handle = loadedCitiesMap();
    const clustered = { type: "geojson", data: POINTS, cluster: true };

    handle.setSpec("cities", clustered);
    await settle();

    const rebuild = sequence(handle.map, ["removeLayer", "removeSource", "addSource", "addLayer"]);

    assert.deepEqual(rebuild, [
      ["removeLayer", "cities-circles"],
      ["removeLayer", "cities-labels"],
      ["removeSource", "cities"],
      ["addSource", "cities"],
      ["addLayer", "cities-circles"],
      ["addLayer", "cities-labels"],
    ]);
    assert.deepEqual(handle.map.getSource("cities").spec, clustered);
    assert.deepEqual(handle.map.layerIds().sort(), ["cities-circles", "cities-labels"]);
  });

  test("moves a marker in place", async () => {
    const handle = mountMap({ defs: [{ kind: "marker", key: "pin", spec: { lngLat: [0, 0] } }] });
    const [marker] = handle.map.markers;

    handle.setSpec("pin", { lngLat: [2, 3], draggable: true });
    await settle();

    assert.deepEqual([...handle.map.markers], [marker]);
    assert.deepEqual(marker.getLngLat(), { lng: 2, lat: 3 });
    assert.deepEqual(marker.calls.slice(1), [
      ["setLngLat", [2, 3]],
      ["setDraggable", true],
    ]);
  });

  test("replaces a marker whose colour changes", async () => {
    const handle = mountMap({
      defs: [{ kind: "marker", key: "pin", spec: { lngLat: [0, 0], color: "#e11d48" } }],
    });
    const [before] = handle.map.markers;

    handle.setSpec("pin", { lngLat: [0, 0], color: "#2563eb" });
    await settle();

    const [after] = handle.map.markers;
    assert.equal(handle.map.markers.size, 1);
    assert.notEqual(after, before);
    assert.equal(after.options.color, "#2563eb");
    assert.equal(before.map, null);
  });

  test("applies a marker's opacity, alignment and subpixel changes in place", async () => {
    const handle = mountMap({
      defs: [{ kind: "marker", key: "pin", spec: { lngLat: [0, 0], opacity: "1" } }],
    });
    const [marker] = handle.map.markers;

    handle.setSpec("pin", {
      lngLat: [0, 0],
      opacity: "0.4",
      rotationAlignment: "map",
      subpixelPositioning: true,
    });
    await settle();

    assert.deepEqual([...handle.map.markers], [marker]);
    assert.equal(marker.opacity, "0.4");
    assert.equal(marker.rotationAlignment, "map");
    // An unset pitch alignment follows the rotation alignment, as it does
    // when MapLibre builds the marker.
    assert.equal(marker.pitchAlignment, "map");
    assert.equal(marker.subpixelPositioning, true);

    handle.setSpec("pin", { lngLat: [0, 0], pitchAlignment: "viewport" });
    await settle();

    assert.deepEqual([...handle.map.markers], [marker]);
    assert.equal(marker.opacity, "1");
    assert.equal(marker.rotationAlignment, "auto");
    assert.equal(marker.pitchAlignment, "viewport");
    assert.equal(marker.subpixelPositioning, false);
  });

  test("attaches, updates and detaches a marker's popup as its html changes", async () => {
    const handle = mountMap({ defs: [{ kind: "marker", key: "pin", spec: { lngLat: [0, 0] } }] });
    const [marker] = handle.map.markers;

    handle.setSpec("pin", { lngLat: [0, 0], popup: { html: "<p>One</p>", options: {} } });
    await settle();

    const popup = marker.getPopup();
    assert.equal(popup.html, "<p>One</p>");

    handle.setSpec("pin", { lngLat: [0, 0], popup: { html: "<p>Two</p>", options: {} } });
    await settle();

    assert.equal(marker.getPopup(), popup);
    assert.equal(popup.html, "<p>Two</p>");

    handle.setSpec("pin", { lngLat: [0, 0] });
    await settle();

    assert.equal(marker.getPopup(), null);
    assert.deepEqual([...handle.map.markers], [marker]);
  });

  test("replaces a marker's popup whose options change, keeping it open", async () => {
    const popup = (options) => ({ html: "<p>Depot</p>", options });
    const handle = mountMap({
      defs: [{ kind: "marker", key: "pin", spec: { lngLat: [0, 0], popup: popup({}) } }],
    });
    const [marker] = handle.map.markers;
    const before = marker.getPopup();

    // The user clicks the marker.
    marker.togglePopup();
    handle.setSpec("pin", { lngLat: [0, 0], popup: popup({ maxWidth: "320px" }) });
    await settle();

    const after = marker.getPopup();
    assert.notEqual(after, before);
    assert.equal(after.options.maxWidth, "320px");
    assert.equal(after.html, "<p>Depot</p>");
    assert.ok(after.isOpen());
    assert.ok(!before.isOpen());
    assert.deepEqual([...handle.map.popups], [after]);
  });

  test("applies a popup's width, offset, class and subpixel changes in place", async () => {
    const spec = { lngLat: [0, 0], html: "<p>Hi</p>" };
    const handle = mountMap({
      defs: [{ ...INFO, spec: { ...spec, maxWidth: "200px", className: "info wide" } }],
    });
    const [popup] = handle.map.popups;
    dispatched.length = 0;

    handle.setSpec("info", {
      ...spec,
      maxWidth: "320px",
      offset: 12,
      className: "info narrow",
      subpixelPositioning: true,
    });
    await settle();

    assert.deepEqual([...handle.map.popups], [popup]);
    assert.equal(popup.options.maxWidth, "320px");
    assert.equal(popup.options.offset, 12);
    assert.deepEqual([...popup.classes].sort(), ["info", "narrow"]);
    assert.equal(popup.options.subpixelPositioning, true);

    handle.setSpec("info", spec);
    await settle();

    assert.deepEqual([...handle.map.popups], [popup]);
    // MapLibre's own default; without a value its container keeps the old one.
    assert.equal(popup.options.maxWidth, "240px");
    assert.equal(popup.options.offset, undefined);
    assert.deepEqual([...popup.classes], []);
    assert.equal(popup.options.subpixelPositioning, false);
    assert.deepEqual(dispatched, []);
  });

  test("replaces an open popup whose close options change, reporting no close or open", async () => {
    const handle = mountMap({ defs: [INFO] });
    const [before] = handle.map.popups;
    dispatched.length = 0;

    handle.setSpec("info", { ...INFO.spec, closeButton: false, closeOnClick: false });
    await settle();

    const [after] = handle.map.popups;
    assert.equal(handle.map.popups.size, 1);
    assert.notEqual(after, before);
    assert.ok(after.isOpen());
    assert.deepEqual(after.options, { closeButton: false, closeOnClick: false });
    assert.equal(after.html, "<p>One</p>");
    assert.deepEqual(dispatched, []);

    // Its events now come from the new popup, and only from it.
    after.remove();
    assert.deepEqual(dispatched, [["closed", "page", {}]]);
    assert.equal(before.listenerCount("close") + before.listenerCount("open"), 0);
  });

  test("updates an open popup, and reopens one MapLibre closed when it changes", async () => {
    const handle = mountMap({
      defs: [{ kind: "popup", key: "info", spec: { lngLat: [0, 0], html: "<p>One</p>" } }],
    });
    const [first] = handle.map.popups;

    handle.setSpec("info", { lngLat: [1, 1], html: "<p>Two</p>" });
    await settle();

    assert.deepEqual([...handle.map.popups], [first]);
    assert.equal(first.html, "<p>Two</p>");

    // The close button, a map click or a camera move.
    first.remove();
    handle.setSpec("info", { lngLat: [1, 1], html: "<p>Three</p>" });
    await settle();

    const [reopened] = handle.map.popups;
    assert.equal(handle.map.popups.size, 1);
    assert.ok(reopened.isOpen());
    assert.equal(reopened.html, "<p>Three</p>");
  });

  test("moves the camera without animating when a camera prop changes", async () => {
    const handle = mountMap({ spec: { style: STYLE, center: [0, 0], zoom: 3 } });

    handle.setSpec("map", { style: STYLE, center: [10, 20], zoom: 3 });
    await settle();

    assert.deepEqual(handle.map.callsTo("jumpTo"), [
      [{ center: [10, 20] }, { holoMapReconciled: true }],
    ]);
    assert.deepEqual(handle.map.callsTo("setStyle"), []);
  });
});

describe("remove", () => {
  test("removes a layer whose definition goes away, keeping its source", async () => {
    const handle = loadedCitiesMap();

    handle.remove("cities-labels");
    await settle();

    assert.deepEqual(handle.map.callsTo("removeLayer"), [["cities-labels"]]);
    assert.deepEqual(handle.map.layerIds(), ["cities-circles"]);
    assert.ok(handle.map.getSource("cities"));
  });

  test("takes a source's layers off before the source itself", async () => {
    const handle = loadedCitiesMap();

    handle.remove("cities");
    handle.remove("cities-circles");
    handle.remove("cities-labels");
    await settle();

    assert.deepEqual(sequence(handle.map, ["removeLayer", "removeSource"]), [
      ["removeLayer", "cities-circles"],
      ["removeLayer", "cities-labels"],
      ["removeSource", "cities"],
    ]);
    assert.deepEqual(handle.map.layerIds(), []);
    assert.equal(handle.map.getSource("cities"), undefined);
  });

  test("takes markers, popups and controls off the map", async () => {
    const handle = mountMap({
      defs: [
        { kind: "marker", key: "pin", spec: { lngLat: [0, 0] } },
        { kind: "popup", key: "info", spec: { lngLat: [0, 0], html: "<p>Hi</p>" } },
        { kind: "control", key: "scale", spec: { control: "scale" } },
      ],
    });
    const control = handle.map.controls[0].control;

    handle.remove("pin");
    handle.remove("info");
    handle.remove("scale");
    await settle();

    assert.equal(handle.map.markers.size, 0);
    assert.equal(handle.map.popups.size, 0);
    assert.deepEqual(handle.map.callsTo("removeControl"), [[control]]);
    assert.deepEqual(handle.map.controls, []);
  });
});

// MapLibre refuses a layer whose source it does not hold. The runtime holds
// the layer back instead, and adds it when the source appears.
describe("layers waiting for their source", () => {
  test("adds a layer written above its source once the source is added", () => {
    const { map } = mountMap({ defs: [CIRCLES, SOURCE, LABELS] });

    map.loadStyle();

    assert.deepEqual(map.layerIds(), ["cities-circles", "cities-labels"]);
  });

  test("adds layers rendered without their source once the source is rendered", async () => {
    const handle = mountMap({ defs: [CIRCLES, LABELS] });
    handle.map.loadStyle();

    assert.deepEqual(handle.map.layerIds(), []);

    handle.add(SOURCE);
    await settle();

    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "cities-labels"]);
  });

  test("restores a source's layers in declared order when it is rendered again", async () => {
    const handle = loadedCitiesMap();

    handle.remove("cities");
    await settle();

    assert.deepEqual(handle.map.layerIds(), []);
    assert.equal(handle.map.getSource("cities"), undefined);

    handle.add(SOURCE);
    await settle();

    assert.ok(handle.map.getSource("cities"));
    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "cities-labels"]);
  });
});

// Layers stack in template order, `before_id` aside, and controls stack in a
// corner in declared order, however late each one reaches the map.
describe("order", () => {
  const HIGHLIGHT = {
    kind: "layer",
    key: "cities-highlight",
    spec: { type: "circle", source: "cities", paint: { "circle-radius": 9 } },
  };

  const HALO = { kind: "layer", key: "cities-halo", spec: { type: "circle", source: "cities" } };

  // Circles beneath the labels, which are declared after them.
  const CIRCLES_UNDER_LABELS = {
    ...CIRCLES,
    spec: { ...CIRCLES.spec, beforeId: "cities-labels" },
  };

  test("adds a layer rendered later at its place in the template", async () => {
    const handle = loadedCitiesMap();

    handle.add(HIGHLIGHT, "cities-labels");
    await settle();

    assert.deepEqual(handle.map.layerIds(), [
      "cities-circles",
      "cities-highlight",
      "cities-labels",
    ]);
  });

  test("re-adds a layer whose type changes at its place", async () => {
    const handle = loadedCitiesMap();

    handle.setSpec("cities-circles", { type: "heatmap", source: "cities" });
    await settle();

    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "cities-labels"]);
  });

  test("keeps the layers of a rebuilt source where they were", async () => {
    const handle = mountMap({
      defs: [
        SOURCE,
        CIRCLES,
        { kind: "source", key: "roads", spec: { type: "geojson", data: POINTS } },
        { kind: "layer", key: "roads-lines", spec: { type: "line", source: "roads" } },
        LABELS,
      ],
    });
    handle.map.loadStyle();

    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "roads-lines", "cities-labels"]);

    handle.setSpec("cities", { type: "geojson", data: POINTS, cluster: true });
    await settle();

    assert.deepEqual(handle.map.callsTo("removeSource"), [["cities"]]);
    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "roads-lines", "cities-labels"]);
  });

  test("moves a layer when its before_id changes", async () => {
    const handle = mountMap({ defs: [SOURCE, CIRCLES, LABELS] });
    handle.map.loadStyle({
      layers: [
        { id: "water", type: "background" },
        { id: "places", type: "background" },
      ],
    });

    handle.setSpec("cities-circles", { ...CIRCLES.spec, beforeId: "places" });
    await settle();

    assert.deepEqual(handle.map.layerIds(), ["water", "cities-circles", "places", "cities-labels"]);

    handle.setSpec("cities-circles", CIRCLES.spec);
    await settle();

    assert.deepEqual(handle.map.layerIds(), ["water", "places", "cities-circles", "cities-labels"]);
    assert.deepEqual(handle.map.callsTo("removeLayer"), []);
  });

  test("puts a layer beneath a before_id layer declared after it", () => {
    const { map } = mountMap({ defs: [SOURCE, CIRCLES_UNDER_LABELS, HALO, LABELS] });

    map.loadStyle();

    assert.deepEqual(map.layerIds(), ["cities-halo", "cities-circles", "cities-labels"]);
  });

  test("puts a layer beneath its before_id layer once that layer is rendered", async () => {
    const handle = mountMap({ defs: [SOURCE, CIRCLES_UNDER_LABELS, HALO] });
    handle.map.loadStyle();

    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "cities-halo"]);

    handle.add(LABELS);
    await settle();

    assert.deepEqual(handle.map.layerIds(), ["cities-halo", "cities-circles", "cities-labels"]);
  });

  test("puts layers that share a before_id beneath it in declared order", async () => {
    const underLabels = (layer) => ({
      ...layer,
      spec: { ...layer.spec, beforeId: "cities-labels" },
    });
    const handle = mountMap({ defs: [SOURCE, CIRCLES_UNDER_LABELS, underLabels(HALO), HIGHLIGHT] });
    handle.map.loadStyle();

    handle.add(LABELS);
    await settle();

    assert.deepEqual(handle.map.layerIds(), [
      "cities-highlight",
      "cities-circles",
      "cities-halo",
      "cities-labels",
    ]);
  });

  const control =(key, name, position, options = {}) => ({
    kind: "control",
    key,
    spec: { control: name, position, ...options },
  });

  // The controls in a corner, top to bottom, by class.
  const corner = (map, position) =>
    map.controlsIn(position).map((each) => each.constructor.name);

  test("keeps a control's place in its corner when an update replaces it", async () => {
    const handle = mountMap({
      defs: [
        control("nav", "navigation", "top-right"),
        control("full", "fullscreen", "top-right"),
        control("scale", "scale", "bottom-left"),
        control("attribution", "attribution", "bottom-left"),
      ],
    });

    // A bottom corner stacks upwards: the first declared sits at the edge.
    assert.deepEqual(corner(handle.map, "top-right"), ["NavigationControl", "FullscreenControl"]);
    assert.deepEqual(corner(handle.map, "bottom-left"), ["AttributionControl", "ScaleControl"]);

    handle.setSpec("nav", { control: "navigation", position: "top-right", showCompass: false });
    handle.setSpec("scale", { control: "scale", position: "bottom-left", unit: "imperial" });
    await settle();

    assert.deepEqual(corner(handle.map, "top-right"), ["NavigationControl", "FullscreenControl"]);
    assert.deepEqual(corner(handle.map, "bottom-left"), ["AttributionControl", "ScaleControl"]);
    assert.deepEqual(handle.map.controlsIn("top-right")[0].options, { showCompass: false });
    assert.deepEqual(handle.map.controlsIn("bottom-left")[1].options, { unit: "imperial" });
  });

  test("adds a control rendered later at its place in its corner", async () => {
    const handle = mountMap({
      defs: [
        control("nav", "navigation", "top-right"),
        control("locate", "geolocate", "top-right"),
        control("scale", "scale", "bottom-left"),
        control("attribution", "attribution", "bottom-left"),
      ],
    });

    handle.add(control("full", "fullscreen", "top-right"), "locate");
    handle.add(control("globe", "globe", "bottom-left"), "attribution");
    await settle();

    assert.deepEqual(corner(handle.map, "top-right"), [
      "NavigationControl",
      "FullscreenControl",
      "GeolocateControl",
    ]);
    assert.deepEqual(corner(handle.map, "bottom-left"), [
      "AttributionControl",
      "GlobeControl",
      "ScaleControl",
    ]);
  });
});

describe("kind change", () => {
  test("replaces the object when a key is reused for a different kind", async () => {
    const handle = mountMap({ defs: [{ kind: "marker", key: "spot", spec: { lngLat: [0, 0] } }] });
    handle.map.loadStyle();

    const element = handle.def("spot");
    element.setAttribute("data-hm", "popup");
    element.setAttribute("data-hm-spec", JSON.stringify({ lngLat: [0, 0], html: "<p>Spot</p>" }));
    await settle();

    assert.equal(handle.map.markers.size, 0);
    assert.equal(handle.map.popups.size, 1);
    assert.equal([...handle.map.popups][0].html, "<p>Spot</p>");
  });

  test("keeps the new object when a key changes kind before the style has loaded", async () => {
    const handle = mountMap({
      defs: [{ kind: "source", key: "spot", spec: { type: "geojson", data: POINTS } }],
    });

    const element = handle.def("spot");
    element.setAttribute("data-hm", "marker");
    element.setAttribute("data-hm-spec", JSON.stringify({ lngLat: [1, 2] }));
    element.setAttribute(
      "data-hm-events",
      JSON.stringify({ click: { action: "spotted", target: "page" } }),
    );
    await settle();
    handle.map.loadStyle();

    const [marker] = handle.map.markers;
    assert.equal(handle.map.markers.size, 1);
    assert.equal(handle.map.getSource("spot"), undefined);

    await userClick(marker.getElement());
    assert.deepEqual(dispatched, [["spotted", "page", { lng_lat: [1, 2] }]]);

    handle.remove("spot");
    await settle();

    assert.equal(handle.map.markers.size, 0);
  });
});

// MapLibre keeps sources, layers and images apart, so one id can name one of
// each, and terrain and sky are not named at all.
describe("shared ids", () => {
  const PARCELS = {
    kind: "source",
    key: "parcels",
    spec: { type: "geojson", data: POINTS },
  };

  const PARCELS_FILL = {
    kind: "layer",
    key: "parcels",
    spec: { type: "fill", source: "parcels", paint: { "fill-color": "#3b82f6" } },
  };

  const REBUILDS = ["addSource", "removeSource", "addLayer", "removeLayer"];

  test("keeps a source and a layer that share an id, across re-renders", async () => {
    const handle = mountMap({ defs: [PARCELS, PARCELS_FILL] });
    handle.map.loadStyle();

    assert.deepEqual(handle.map.getSource("parcels").spec, PARCELS.spec);
    assert.deepEqual(handle.map.layerIds(), ["parcels"]);

    handle.map.calls.length = 0;
    const red = { ...PARCELS_FILL.spec, paint: { "fill-color": "#ef4444" } };
    handle.setSpec("parcels", red, "layer");
    handle.setSpec("parcels", { type: "geojson", data: MORE_POINTS }, "source");
    await settle();

    assert.deepEqual(sequence(handle.map, REBUILDS), []);
    assert.deepEqual(handle.map.callsTo("setPaintProperty"), [
      ["parcels", "fill-color", "#ef4444"],
    ]);
    assert.deepEqual(handle.map.callsTo("setData"), [["parcels", MORE_POINTS]]);
    assert.deepEqual(handle.map.layerIds(), ["parcels"]);
  });

  test("keeps an image, a source and a layer that share an id", async () => {
    const handle = mountMap({
      defs: [
        { kind: "image", key: "stops", spec: { url: "https://tiles.test/stop.png" } },
        { kind: "source", key: "stops", spec: { type: "geojson", data: POINTS } },
        {
          kind: "layer",
          key: "stops",
          spec: { type: "symbol", source: "stops", layout: { "icon-image": "stops" } },
        },
      ],
    });
    handle.map.loadStyle();
    await settle();

    assert.deepEqual(handle.map.images.get("stops").image, { url: "https://tiles.test/stop.png" });
    assert.ok(handle.map.getSource("stops"));
    assert.deepEqual(handle.map.layerIds(), ["stops"]);
  });

  test("keeps layers called terrain and sky next to the Terrain and Sky components", async () => {
    const terrain = { source: "dem", exaggeration: 1.4 };
    const sky = { "sky-color": "#199EF3" };
    const handle = mountMap({
      defs: [
        { kind: "source", key: "dem", spec: { type: "raster-dem", tiles: ["https://dem.test"] } },
        { kind: "layer", key: "terrain", spec: { type: "hillshade", source: "dem" } },
        { kind: "terrain", key: "terrain", spec: terrain },
        { kind: "layer", key: "sky", spec: { type: "background" } },
        { kind: "sky", key: "sky", spec: sky },
      ],
    });
    handle.map.loadStyle();

    assert.deepEqual(handle.map.callsTo("setTerrain"), [[terrain]]);
    assert.deepEqual(handle.map.callsTo("setSky"), [[sky]]);
    assert.deepEqual(handle.map.layerIds(), ["terrain", "sky"]);

    handle.map.calls.length = 0;
    handle.setSpec("terrain", { ...terrain, exaggeration: 2 }, "terrain");
    await settle();

    assert.deepEqual(handle.map.callsTo("setTerrain"), [[{ ...terrain, exaggeration: 2 }]]);
    assert.deepEqual(sequence(handle.map, REBUILDS), []);
    assert.deepEqual(handle.map.layerIds(), ["terrain", "sky"]);
  });
});

describe("style reload", () => {
  test("re-declares its sources and layers in template order when a new style loads", async () => {
    const handle = loadedCitiesMap([{ kind: "marker", key: "pin", spec: { lngLat: [0, 0] } }]);
    const [marker] = handle.map.markers;

    handle.setSpec("map", { style: "https://tiles.test/dark.json" });
    await settle();

    assert.deepEqual(
      handle.map.callsTo("setStyle").map(([style]) => style),
      ["https://tiles.test/dark.json"],
    );

    handle.map.calls.length = 0;
    handle.map.loadStyle({ layers: [{ id: "background", type: "background" }] });

    assert.deepEqual(sequence(handle.map, ["addSource", "addLayer"]), [
      ["addSource", "cities"],
      ["addLayer", "cities-circles"],
      ["addLayer", "cities-labels"],
    ]);
    assert.deepEqual(handle.map.callsTo("addSource"), [["cities", SOURCE.spec]]);
    assert.deepEqual(handle.map.layerIds(), ["background", "cities-circles", "cities-labels"]);
    assert.deepEqual([...handle.map.markers], [marker]);
  });

  test("leaves an id the new style already uses to that style, with a warning", () => {
    // Only the source is declared. Layers on it would be re-added to the
    // style's vector source, which refuses a layer with no "source-layer".
    const handle = mountMap({ defs: [SOURCE] });
    handle.map.loadStyle();
    handle.map.calls.length = 0;

    handle.map.loadStyle({
      sources: { cities: { type: "vector", url: "https://tiles.test/cities.json" } },
    });

    assert.deepEqual(handle.map.callsTo("addSource"), []);
    assert.equal(handle.map.getSource("cities").type, "vector");
    assert.equal(logged.warnings.length, 1);
    assert.match(logged.warnings[0], /the new style already defines a source called "cities"/);
  });

  const DARK = "https://tiles.test/dark.json";

  test("leaves an unchanged inline style alone when another map prop changes", async () => {
    const inline = { version: 8, sources: {}, layers: [{ id: "background", type: "background" }] };
    const handle = mountMap({ spec: { style: inline, zoom: 3 }, defs: [SOURCE, CIRCLES, LABELS] });
    handle.map.loadStyle(inline);
    handle.map.calls.length = 0;

    handle.setSpec("map", { style: inline, zoom: 5 });
    await settle();

    // Set again, MapLibre would diff it against the map and take off every
    // source and layer the style itself does not carry.
    assert.deepEqual(handle.map.callsTo("setStyle"), []);
    assert.deepEqual(sequence(handle.map, ["addSource", "addLayer"]), []);
    assert.deepEqual(handle.map.callsTo("jumpTo"), [[{ zoom: 5 }, { holoMapReconciled: true }]]);
    assert.deepEqual(handle.map.layerIds(), ["background", "cities-circles", "cities-labels"]);

    const changed = { ...inline, layers: [{ id: "land", type: "background" }] };
    handle.setSpec("map", { style: changed, zoom: 5 });
    await settle();

    assert.deepEqual(handle.map.callsTo("setStyle"), [[changed, { diff: false }]]);
  });

  test("declares terrain and sky again with the rest, warning about nothing it owns", async () => {
    const terrain = { source: "dem", exaggeration: 1.4 };
    const sky = { "sky-color": "#199EF3" };
    const handle = mountMap({
      defs: [
        SOURCE,
        CIRCLES,
        LABELS,
        { kind: "source", key: "dem", spec: { type: "raster-dem", tiles: ["https://dem.test"] } },
        { kind: "terrain", key: "terrain", spec: terrain },
        { kind: "sky", key: "sky", spec: sky },
      ],
    });
    handle.map.loadStyle();

    handle.setSpec("map", { style: DARK });
    await settle();
    handle.map.calls.length = 0;
    handle.map.loadStyle({ layers: [{ id: "background", type: "background" }] });

    assert.deepEqual(handle.map.layerIds(), ["background", "cities-circles", "cities-labels"]);
    assert.ok(handle.map.getSource("cities"));
    assert.ok(handle.map.getSource("dem"));
    assert.deepEqual(handle.map.callsTo("setTerrain"), [[terrain]]);
    assert.deepEqual(handle.map.callsTo("setSky"), [[sky]]);
    assert.deepEqual(logged.warnings, []);
  });

  test("holds definitions and HoloMap.API calls that come while a new style loads", async () => {
    const handle = loadedCitiesMap();

    handle.setSpec("map", { style: DARK });
    await settle();
    handle.add({ kind: "layer", key: "cities-halo", spec: { type: "circle", source: "cities" } });
    await settle();
    runtime.invoke(handle.cid, "setPaintProperty", ["cities-circles", "circle-radius", 9]);

    handle.map.loadStyle();

    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "cities-labels", "cities-halo"]);
    assert.equal(handle.map.getLayer("cities-circles").paint["circle-radius"], 9);
  });

  test("swaps the style for HoloMap.API.set_style/2 the same way", () => {
    const handle = loadedCitiesMap();

    runtime.invoke(handle.cid, "setStyle", [DARK]);
    runtime.invoke(handle.cid, "setPaintProperty", ["cities-circles", "circle-radius", 9]);
    handle.map.loadStyle();

    // Never a diff, so `style.load` always follows and nothing is lost.
    assert.deepEqual(handle.map.callsTo("setStyle"), [[DARK, { diff: false }]]);
    assert.deepEqual(handle.map.layerIds(), ["cities-circles", "cities-labels"]);
    assert.equal(handle.map.getLayer("cities-circles").paint["circle-radius"], 9);
  });

  test("runs the calls queued after a set_style/2 on the style it asked for", () => {
    const { cid, map } = mountMap({ defs: [SOURCE, CIRCLES, LABELS] });

    runtime.invoke(cid, "setStyle", [DARK]);
    runtime.invoke(cid, "setPaintProperty", ["cities-circles", "circle-radius", 9]);
    map.loadStyle();

    assert.deepEqual(map.callsTo("setPaintProperty"), []);

    map.loadStyle();

    assert.deepEqual(map.layerIds(), ["cities-circles", "cities-labels"]);
    assert.equal(map.getLayer("cities-circles").paint["circle-radius"], 9);
  });

  test("leaves the layers of a source the new style took over off the map, naming them", async () => {
    const handle = loadedCitiesMap();

    handle.setSpec("map", { style: DARK });
    await settle();
    handle.map.calls.length = 0;
    // A basemap's vector source refuses a layer with no "source-layer".
    handle.map.loadStyle({
      sources: { cities: { type: "vector", url: "https://tiles.test/cities.json" } },
    });

    assert.deepEqual(handle.map.callsTo("addLayer"), []);
    assert.deepEqual(handle.map.layerIds(), []);
    assert.equal(logged.warnings.length, 1);
    assert.match(logged.warnings[0], /the new style already defines a source called "cities"/);
    assert.match(logged.warnings[0], /"cities-circles", "cities-labels"/);

    // Nor does a later change to one of them put it on the style's source.
    handle.setSpec("cities-circles", { ...CIRCLES.spec, paint: { "circle-radius": 6 } });
    await settle();

    assert.deepEqual(handle.map.layerIds(), []);
  });
});

describe("events", () => {
  test("dispatches map events with the camera, except for moves the runtime made", async () => {
    const handle = mountMap({
      spec: { style: STYLE, zoom: 3 },
      events: { moveend: { action: "moved", target: "page", params: { from: "map" } } },
    });

    handle.map.fire("moveend", {});

    assert.deepEqual(dispatched, [
      [
        "moved",
        "page",
        {
          from: "map",
          center: [0, 0],
          zoom: 0,
          bearing: 0,
          pitch: 0,
          bounds: [
            [-10, -5],
            [10, 5],
          ],
        },
      ],
    ]);

    dispatched.length = 0;
    handle.setSpec("map", { style: STYLE, zoom: 7 });
    await settle();

    assert.equal(handle.map.callsTo("jumpTo").length, 1);
    assert.deepEqual(dispatched, []);
  });

  test("binds layer events to their layer and unbinds them with it", async () => {
    const handle = mountMap({
      defs: [SOURCE, { ...CIRCLES, events: { click: { action: "picked", target: "page" } } }],
    });
    handle.map.loadStyle();

    assert.equal(handle.map.listenerCount("click", "cities-circles"), 1);

    const feature = {
      id: 7,
      source: "cities",
      properties: { name: "Santo Domingo" },
      geometry: POINTS.features[0].geometry,
    };

    handle.map.fire(
      "click",
      { lngLat: { lng: -69.9, lat: 18.5 }, point: { x: 120, y: 80 }, features: [feature] },
      "cities-circles",
    );

    assert.deepEqual(dispatched, [
      [
        "picked",
        "page",
        {
          layer: "cities-circles",
          lng_lat: [-69.9, 18.5],
          point: [120, 80],
          features: [{ ...feature, source_layer: null }],
        },
      ],
    ]);

    handle.remove("cities-circles");
    await settle();

    assert.equal(handle.map.listenerCount("click", "cities-circles"), 0);
  });

  // Each of these makes the runtime replace the MapLibre marker, and the new
  // one comes with a new element and a new emitter to bind the events to.
  const DEPOT = { lngLat: [-69.9, 18.5], color: "#e11d48", scale: 1, className: "depot" };

  const rebuilds = {
    "slot content": (handle) => {
      handle.def("depot").querySelector("[data-hm-content]").innerHTML = "<b>3 pending</b>";
    },
    color: (handle) => handle.setSpec("depot", { ...DEPOT, color: "#2563eb" }),
    scale: (handle) => handle.setSpec("depot", { ...DEPOT, scale: 1.5 }),
    "class name": (handle) => handle.setSpec("depot", { ...DEPOT, className: "depot busy" }),
    // MapLibre has no setter for these two.
    anchor: (handle) => handle.setSpec("depot", { ...DEPOT, anchor: "bottom" }),
    "click tolerance": (handle) => handle.setSpec("depot", { ...DEPOT, clickTolerance: 5 }),
  };

  Object.entries(rebuilds).forEach(([change, apply]) => {
    test(`keeps a marker's events bound when a change to its ${change} replaces it`, async () => {
      const handle = mountMap({
        defs: [
          {
            kind: "marker",
            key: "depot",
            spec: DEPOT,
            events: MARKER_EVENTS,
            content: "<b>2 pending</b>",
          },
        ],
      });
      const [before] = handle.map.markers;

      apply(handle);
      await settle();

      const [after] = handle.map.markers;
      assert.equal(handle.map.markers.size, 1);
      assert.notEqual(after, before);

      await clickAndDrag(after);

      assert.deepEqual(
        dispatched.map(([action]) => action),
        ["picked", "drag_started", "dragged", "dropped"],
      );
      assert.deepEqual(dispatched[0][2], { lng_lat: [-69.9, 18.5] });
      assert.equal(markerListeners(before), 0, "listeners left on the discarded marker");
    });
  });

  const OFFICE = {
    kind: "marker",
    key: "office",
    spec: { lngLat: [-70.66, 19.45], popup: { html: "<p>Office</p>", options: {} } },
    events: { click: { action: "office_clicked", target: "page" } },
  };

  test("opens a marker's popup on click, as well as dispatching its on_click", async () => {
    const { map } = mountMap({ defs: [OFFICE] });
    const [marker] = map.markers;

    await userClick(marker.getElement());

    assert.deepEqual(dispatched, [["office_clicked", "page", { lng_lat: [-70.66, 19.45] }]]);
    assert.ok(marker.getPopup().isOpen());
  });

  test("closes a close_on_click popup when a marker with on_click is clicked", async () => {
    const { map } = mountMap({ defs: [INFO, { ...OFFICE, spec: { lngLat: [-70.66, 19.45] } }] });
    const [popup] = map.popups;
    const [marker] = map.markers;
    dispatched.length = 0;

    await userClick(marker.getElement());

    assert.ok(!popup.isOpen());
    assert.deepEqual(
      dispatched.map(([action]) => action),
      ["closed", "office_clicked"],
    );
  });

  // The pattern HoloMap.Popup documents and the markers demo follows: a click
  // on a marker selects it, and the popup showing the selection clears it when
  // MapLibre closes it. Hologram runs actions in the order they are dispatched,
  // so a click on another marker leaves that marker selected only if the close
  // it causes is reported first.
  test("reports a marker click after the close of the popup that click dismisses", async () => {
    const place = (key, name, lngLat) => ({
      kind: "marker",
      key,
      spec: { lngLat },
      events: { click: { action: "select", target: "page", params: { name } } },
    });

    const { map } = mountMap({
      defs: [
        place("santiago", "Santiago", [-70.7, 19.45]),
        place("punta-cana", "Punta Cana", [-68.37, 18.58]),
        {
          kind: "popup",
          key: "details",
          spec: { lngLat: [-70.7, 19.45] },
          events: { close: { action: "clear", target: "page" } },
          content: "<h3>Santiago</h3>",
        },
      ],
    });
    const [popup] = map.popups;
    const [, puntaCana] = map.markers;

    await userClick(puntaCana.getElement());

    assert.ok(!popup.isOpen());
    assert.deepEqual(dispatched, [
      ["clear", "page", {}],
      ["select", "page", { name: "Punta Cana", lng_lat: [-68.37, 18.58] }],
    ]);
  });

  test("reports a marker click to the marker alone, not to the map or a layer under it", async () => {
    const handle = mountMap({
      events: { click: { action: "map_clicked", target: "page" } },
      defs: [
        SOURCE,
        { ...CIRCLES, events: { click: { action: "picked", target: "page" } } },
        OFFICE,
      ],
    });
    handle.map.loadStyle();
    handle.map.featuresUnderPointer = {
      "cities-circles": [{ id: 7, source: "cities", properties: {}, geometry: null }],
    };
    const [marker] = handle.map.markers;

    await userClick(marker.getElement());

    assert.deepEqual(
      dispatched.map(([action]) => action),
      ["office_clicked"],
    );

    // A click anywhere else on the map still reaches both.
    dispatched.length = 0;
    handle.map.getCanvasContainer().dispatchEvent({ type: "click" });

    assert.deepEqual(
      dispatched.map(([action]) => action),
      ["map_clicked", "picked"],
    );
  });

  test("dispatches on_open when a popup first renders and when a change reopens it", async () => {
    const handle = mountMap({ defs: [INFO] });
    const [popup] = handle.map.popups;

    assert.deepEqual(dispatched, [["shown", "page", {}]]);

    // The close button, a map click or a camera move.
    popup.remove();
    handle.setSpec("info", { lngLat: [1, 1], html: "<p>Two</p>" });
    await settle();

    assert.deepEqual(
      dispatched.map(([action]) => action),
      ["shown", "closed", "shown"],
    );
  });

  test("dispatches on_close when MapLibre closes a popup, not when it stops being rendered", async () => {
    const handle = mountMap({ defs: [INFO] });
    const [popup] = handle.map.popups;
    dispatched.length = 0;

    popup.remove();
    assert.deepEqual(dispatched, [["closed", "page", {}]]);

    dispatched.length = 0;
    handle.setSpec("info", { lngLat: [1, 1], html: "<p>Two</p>" });
    await settle();
    dispatched.length = 0;

    handle.remove("info");
    await settle();

    assert.equal(handle.map.popups.size, 0);
    assert.deepEqual(dispatched, []);
  });
});

describe("teardown", () => {
  test("destroy/1 removes the map and detaches its listeners", () => {
    const handle = mountMap({ events: { moveend: { action: "moved" } } });

    runtime.destroy(handle.cid);

    assert.ok(handle.map.removed);
    assert.equal(runtime.instance(handle.cid), null);
    assert.equal(handle.map.listenerCount("moveend"), 0);
  });

  test("tears the map down when its container leaves the document", async () => {
    const handle = mountMap();

    handle.wrapper.remove();
    await settle();

    assert.ok(handle.map.removed);
    assert.equal(runtime.instance(handle.cid), null);
  });
});
