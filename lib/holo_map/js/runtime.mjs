// HoloMap browser runtime.
//
// Hologram gives components an `init` hook but no "props changed" or "about to
// unmount" hook, and its JS interop only runs inside action handlers. A map
// library needs all three: it has to build an instance on mount, push every
// prop change into it, and tear it down when the page moves on.
//
// So HoloMap does not drive MapLibre from Elixir call sites. Every child
// component renders one hidden marker element carrying a JSON specification,
// and this file reconciles those elements against a live MapLibre instance:
//
//   * a marker element appears   -> add the source / layer / marker / control
//   * its `data-hm-spec` changes -> apply the narrowest MapLibre update
//   * it disappears              -> remove the corresponding map object
//   * the container leaves the DOM -> map.remove()
//
// Hologram's virtual DOM writes the attributes; a MutationObserver reads them.
// That covers mount, update and unmount without any framework hook, and it
// works with the vDOM rather than against it — Hologram already preserves
// JS-managed children of an element that stays in the template.

// MapLibre GL JS 6 exposes named exports only — the default export that
// version 4 shipped is gone, and importing it fails the bundle outright.
import {
  setWorkerUrl,
  Map as MapLibreMap,
  Marker as MapLibreMarker,
  Popup as MapLibrePopup,
  NavigationControl,
  ScaleControl,
  GeolocateControl,
  FullscreenControl,
  AttributionControl,
  GlobeControl,
  TerrainControl,
} from "maplibre-gl";

// cid -> MapEntry
const registry = new Map();

const DEF_SELECTOR = "[data-hm]";

// Control kind -> MapLibre constructor. Kept as a table so an unknown control
// fails loudly at the one place that knows the full set.
const CONTROL_CLASSES = {
  navigation: NavigationControl,
  scale: ScaleControl,
  geolocate: GeolocateControl,
  fullscreen: FullscreenControl,
  attribution: AttributionControl,
  globe: GlobeControl,
  terrain: TerrainControl,
};

// Layer specification keys that MapLibre cannot change in place. Any of these
// moving forces a remove-and-re-add of the layer.
const LAYER_IMMUTABLE_KEYS = ["type", "source", "source-layer"];

// Marker options whose change replaces the marker, as a change to the slot
// content does. MapLibre reads `color`, `scale`, `anchor` and `clickTolerance`
// only while building the marker, with no setter to change them afterwards,
// and `color` and `scale` only shape the default pin. `className` does have
// setters (`addClassName`, `removeClassName`, `toggleClassName`), but a change
// to it replaces the marker all the same, so the new classes are applied the
// way the first ones were, while MapLibre builds the marker.
const MARKER_REBUILD_KEYS = ["color", "scale", "className", "anchor", "clickTolerance"];

// Popup options MapLibre reads only while building or opening a popup, with no
// setter to change them afterwards. A change to any of them replaces the popup.
const POPUP_REBUILD_KEYS = [
  "anchor",
  "closeButton",
  "closeOnClick",
  "closeOnMove",
  "focusAfterOpen",
];

// Definition kinds that live inside the style, and so cannot be applied until
// MapLibre has parsed one. Markers, popups and controls are plain DOM overlays
// that attach to the map object itself and need no style at all — queueing
// them would mean a map whose controls never appear if a tile server is slow
// or unreachable.
const STYLE_SCOPED = new Set(["source", "layer", "terrain", "sky", "image"]);

// Marks the MapLibre events that this runtime caused, so they are not reported
// back to the application as if the user had done it.
const RECONCILED = { holoMapReconciled: true };

class MapEntry {
  constructor(cid, container, defs) {
    this.cid = cid;
    this.container = container;
    this.defs = defs;
    this.map = null;
    // Whether the style takes work: false until the first one has loaded,
    // and again while a style change is loading the next one.
    this.styleReady = false;
    // Whether a style has loaded before, so that the next `style.load`
    // follows a style change.
    this.hadStyle = false;
    // Style-scoped work queued while MapLibre is still parsing the style. A
    // page renders its whole component tree before the first byte of style
    // arrives, so the first reconcile always lands early.
    this.pending = [];
    // "kind:id" -> { kind, id, spec, events, encoded, object }. See readDef
    // for why the kind is part of the key.
    this.entities = new Map();
    // Live MapLibre listeners, so they can be detached on teardown.
    this.listeners = [];
    this.observer = null;
    this.disposed = false;
  }
}

// --- public API, imported by HoloMap.Runtime on the Elixir side ------------

// Boots the map for `cid`, or re-attaches to it if it is already running.
//
// Called from HoloMap.Map's mount action. It is safe to call more than once:
// Hologram may re-run the action for a component that is already live, and a
// client-side navigation back to the same page produces a brand new container
// element under the same cid.
export function boot(cid) {
  tryBoot(cid, 1);
}

// How many frames boot waits for a map's container and its definition: about
// a second at 60 frames per second.
const BOOT_ATTEMPTS = 60;

function tryBoot(cid, attempt) {
  const container = document.getElementById(containerId(cid));
  const defs = document.getElementById(defsId(cid));
  // While Hologram morphs one page into another, the map definition can still
  // name the outgoing map (see readDefs). A map built then would get neither
  // its options nor, ever after, its style.
  const mapDef = defs ? readMapDef(defs, cid) : null;

  if (!container || !mapDef) {
    // The action fired before the DOM settled. Hologram patches synchronously,
    // so one frame is usually enough; retrying rather than throwing keeps a
    // slow first paint from turning into a hard error. A page that moves on
    // first leaves nothing to wait for, so the wait is bounded.
    if (attempt < BOOT_ATTEMPTS) {
      requestAnimationFrame(() => tryBoot(cid, attempt + 1));
      return;
    }

    let missing = `a map definition for it in #${defsId(cid)}`;

    if (!container) {
      missing = `#${containerId(cid)}`;
    } else if (!defs) {
      missing = `#${defsId(cid)}`;
    }

    warn(`gave up booting the map "${cid}": ${missing} did not appear within ${attempt} frames`);
    return;
  }

  const existing = registry.get(cid);

  if (existing && !existing.disposed) {
    if (existing.container === container) {
      // Same live map, same node — just make sure it is in sync.
      reconcile(existing);
      return;
    }

    // The cid was re-rendered onto a new node (client-side navigation). The
    // old MapLibre instance is bound to a detached container and must go.
    dispose(existing);
  }

  // Anything already inside the container was left behind by a previous map
  // whose disposal the morph outran. Constructing on top of it would stack a
  // second canvas over the first.
  clearOrphanedCanvas(container);

  const entry = new MapEntry(cid, container, defs);
  registry.set(cid, entry);
  publishGlobalAPI();

  const { workerUrl, ...mapOptions } = mapDef.spec;

  configureWorker(workerUrl);

  entry.map = new MapLibreMap({ ...mapOptions, container });

  // `style.load` is the point MapLibre will accept addSource/addLayer. The
  // `load` event is later and stricter — it also waits for the first complete
  // render, which never arrives if a tile request hangs, and gating on it
  // meant a map that renders but stays permanently empty.
  entry.map.on("style.load", () => {
    entry.styleReady = true;

    if (entry.hadStyle) {
      // A style swap discards every source and layer MapLibre knew about, so
      // the ones this runtime owns have to be declared again from scratch.
      redeclareStyleScoped(entry);
    }

    entry.hadStyle = true;

    // Then the work that waited for this style, in the order it came: on a
    // swap, definitions that changed while it loaded and HoloMap.API calls.
    flush(entry);
    reconcile(entry);
  });

  startObserver(entry);
  ensureLivenessObserver();
  reconcile(entry);

  // After the work for the definitions, so the calls find the sources and
  // layers they name.
  releaseHeldCalls(entry);
}

// Returns the live MapLibre instance for `cid`, or null. This is the seam the
// imperative API (HoloMap.API) goes through.
export function instance(cid) {
  const entry = registry.get(cid);
  return entry && !entry.disposed ? entry.map : null;
}

// A MapLibre plugin — a draw control, a geocoder, a deck.gl overlay — needs the
// raw `maplibregl.Map`, and there is no way to hand it one from Elixir. Every
// booted map is therefore reachable from ordinary JavaScript:
//
//   window.HoloMap.map("explorer").addControl(new MapboxDraw());
//
// It is also what makes a browser test able to assert on what MapLibre actually
// built, rather than on what the DOM happens to look like.
function publishGlobalAPI() {
  if (typeof window === "undefined") {
    return;
  }

  window.HoloMap = window.HoloMap || {};
  window.HoloMap.map = instance;
  window.HoloMap.destroy = destroy;
  window.HoloMap.cids = () =>
    Array.from(registry.entries())
      .filter(([, entry]) => !entry.disposed)
      .map(([cid]) => cid);
}

// Calls `method` on the MapLibre instance for `cid` with `args`, queueing the
// call if the map has not booted or its style has not finished loading.
export function invoke(cid, method, args) {
  const entry = registry.get(cid);

  if (!entry || entry.disposed) {
    holdUntilBoot(cid, method, args);
    return;
  }

  invokeOn(entry, method, args);
}

// cid -> { calls, timer }: the calls made for a map that has not booted yet.
//
// Hologram 0.11 runs the actions components put in place from `init` once
// the page has rendered, in the order of their cids. A page's own action
// (cid "page") therefore runs before the boot of a map whose cid sorts after
// it, and a call it makes for that map arrives first. Calls for a map that
// does not boot in time are dropped, so none reaches a map of the same cid
// rendered later by another page.
const unbooted = new Map();
const UNBOOTED_CALL_TIMEOUT = 5000;

function holdUntilBoot(cid, method, args) {
  let held = unbooted.get(cid);

  if (!held) {
    held = { calls: [], timer: null };
    unbooted.set(cid, held);

    held.timer = setTimeout(() => {
      unbooted.delete(cid);
      const names = held.calls.map(([name]) => `${name}()`).join(", ");
      warn(
        `no map with cid "${cid}" booted within ${UNBOOTED_CALL_TIMEOUT / 1000} seconds, ` +
          `so the calls made for it were dropped: ${names}`,
      );
    }, UNBOOTED_CALL_TIMEOUT);
  }

  held.calls.push([method, args]);
}

// Hands the calls made before `entry`'s map booted to it, in order.
function releaseHeldCalls(entry) {
  const held = unbooted.get(entry.cid);

  if (held) {
    clearTimeout(held.timer);
    unbooted.delete(entry.cid);
    held.calls.forEach(([method, args]) => invokeOn(entry, method, args));
  }
}

function invokeOn(entry, method, args) {
  schedule(entry, "layer", () => {
    const target = entry.map;

    if (method === "setStyle") {
      setStyle(entry, ...(args || []));
      return;
    }

    if (typeof target[method] !== "function") {
      warn(`maplibregl.Map has no method "${method}()"`);
      return;
    }

    target[method](...(args || []));
  });
}

// Tears the map down explicitly. Ordinarily the container observer does this,
// but a caller that knows the map is finished can reclaim the WebGL context
// immediately rather than waiting for the next DOM mutation.
export function destroy(cid) {
  const entry = registry.get(cid);

  if (entry) {
    dispose(entry);
  }
}

// --- reconciliation --------------------------------------------------------

// One observer for every map, watching the document for the removal of a
// container.
//
// The per-map observer below cannot see this: it is aimed at the definitions
// element, and removing an *ancestor* of that element mutates the ancestor's
// parent, not the element itself — so no callback fires and the map keeps its
// WebGL context after Hologram has navigated the page away. Browsers hand out a
// small, fixed number of those contexts, so a leak per navigation is a map that
// eventually refuses to render at all.
//
// The callback is coalesced into one animation frame and then only reads a
// boolean per live map, so it stays cheap on a busy document.
let livenessObserver = null;

function ensureLivenessObserver() {
  if (livenessObserver || typeof MutationObserver === "undefined") {
    return;
  }

  livenessObserver = new MutationObserver(() => {
    // Disposal runs in the observer callback itself rather than a frame later.
    // MutationObserver callbacks are microtasks, so this lands immediately
    // after Hologram's DOM patch and well before the next paint — the window
    // in which a detached map can still emit is as small as it can be made.
    // Reading `isConnected` per live map is cheap enough to do eagerly.
    registry.forEach((entry) => {
      if (!entry.disposed && isStale(entry)) {
        dispose(entry);
      }
    });

    if (registry.size === 0 && livenessObserver) {
      livenessObserver.disconnect();
      livenessObserver = null;
    }
  });

  livenessObserver.observe(document.documentElement, { childList: true, subtree: true });
}

function startObserver(entry) {
  const observer = new MutationObserver(() => {
    if (entry.disposed) {
      return;
    }

    if (!entry.container.isConnected) {
      // Hologram replaced the page under this map. Nothing will call back into
      // this runtime again, so this is the only chance to free the context.
      dispose(entry);
      return;
    }

    reconcile(entry);
  });

  observer.observe(entry.defs, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["data-hm", "data-hm-key", "data-hm-spec", "data-hm-events"],
  });

  entry.observer = observer;
}

function reconcile(entry) {
  if (entry.disposed) {
    return;
  }

  const desired = readDefs(entry);
  const seen = new Set();

  // Every known definition takes its new position before any work runs. Work
  // on a map whose style is ready runs inside the loop below, and a layer or
  // a control is placed by where the others are now declared.
  desired.forEach((def, index) => {
    const known = entry.entities.get(def.key);

    if (known) {
      known.index = index;
    }
  });

  desired.forEach((def, index) => {
    if (def.kind === "map") {
      applyMapDef(entry, def);
      return;
    }

    seen.add(def.key);
    const previous = entry.entities.get(def.key);

    // A definition whose kind changes has a new key, so it is a replacement:
    // the new object is added here and the old one removed below, each from
    // its own record, so neither step can act on the other object.
    if (!previous) {
      entry.entities.set(def.key, {
        kind: def.kind,
        id: def.id,
        spec: def.spec,
        events: def.events,
        encoded: def.encoded,
        element: def.element,
        index,
        object: null,
      });

      schedule(entry, def.kind, () => addEntity(entry, def.key));
      return;
    }

    const specChanged = previous.encoded.spec !== def.encoded.spec;
    const contentChanged = previous.encoded.content !== def.encoded.content;
    const eventsChanged = previous.encoded.events !== def.encoded.events;

    previous.element = def.element;

    if (specChanged || contentChanged) {
      const before = { spec: previous.spec, content: previous.encoded.content };
      previous.spec = def.spec;
      previous.encoded.spec = def.encoded.spec;
      previous.encoded.content = def.encoded.content;
      schedule(entry, def.kind, () => updateEntity(entry, def.key, before));
    }

    if (eventsChanged) {
      previous.events = def.events;
      previous.encoded.events = def.encoded.events;
      schedule(entry, def.kind, () => bindEvents(entry, def.key));
    }
  });

  // Every removed definition is marked before any is taken off the map, so a
  // source removed with its terrain does not warn that the terrain lost it.
  const removed = Array.from(entry.entities).filter(([key]) => !seen.has(key));

  removed.forEach(([, record]) => {
    record.removed = true;
  });

  removed.forEach(([key, record]) => {
    entry.entities.delete(key);
    schedule(entry, record.kind, () => removeEntity(entry, key, record));
  });
}

// Definitions are matched by ownership, not merely by position.
//
// Hologram does not tear the old page's DOM down and build the new one — it
// *morphs* one into the other, patching attributes in place. So during a
// navigation the outgoing map's definition elements briefly carry the incoming
// page's values, and a reconciler that trusted containment alone would read
// them as prop changes on the live map: a camera jump, layers swapped, events
// rebound, all on a map that is about to be discarded.
//
// Every definition therefore names the cid it belongs to in `data-hm-map`, and
// anything that does not name this one is ignored until the dust settles.
function readDefs(entry) {
  return Array.from(entry.defs.querySelectorAll(DEF_SELECTOR))
    .map(readDef)
    .filter((def) => def && def.mapCid === entry.cid);
}

function readMapDef(defs, cid) {
  const element = defs.querySelector('[data-hm="map"]');
  const def = element ? readDef(element) : null;

  return def && def.mapCid === cid ? def : null;
}

function readDef(element) {
  const kind = element.getAttribute("data-hm");

  if (!kind) {
    return null;
  }

  const rawSpec = element.getAttribute("data-hm-spec") || "{}";
  const rawEvents = element.getAttribute("data-hm-events") || "{}";

  const content = contentOf(element);
  const id = element.getAttribute("data-hm-key") || kind;

  return {
    kind,
    mapCid: element.getAttribute("data-hm-map"),
    // MapLibre keeps sources, layers and images in separate namespaces, and a
    // source and the layer drawing it commonly share an id. Definitions are
    // told apart by kind as well, so those never stand for one another; `id`
    // alone is what MapLibre is given.
    key: keyFor(kind, id),
    id,
    spec: parseJSON(rawSpec, {}),
    events: parseJSON(rawEvents, {}),
    encoded: { spec: rawSpec, events: rawEvents, content },
    element,
  };
}

function keyFor(kind, id) {
  return `${kind}:${id}`;
}

// Slot markup for markers and popups, or null when the slot is empty. The
// emptiness check is what decides whether a marker gets MapLibre's default pin
// or a custom element, so it must ignore the whitespace Hologram indents with.
function contentOf(element) {
  const holder = element.querySelector("[data-hm-content]");

  if (!holder) {
    return null;
  }

  const html = holder.innerHTML;
  return html.trim() === "" ? null : html;
}

// --- map-level props -------------------------------------------------------

function applyMapDef(entry, def) {
  const previous = entry.mapEncoded;
  entry.mapEncoded = def.encoded.spec;

  if (previous === undefined) {
    // First pass: these values were already handed to the constructor.
    entry.mapEvents = def.events;
    schedule(entry, "map", () => bindMapEvents(entry));
    return;
  }

  if (previous !== def.encoded.spec) {
    schedule(entry, "map", () => applyMapOptions(entry, def.spec, parseJSON(previous, {})));
  }

  if (JSON.stringify(entry.mapEvents || {}) !== def.encoded.events) {
    entry.mapEvents = def.events;
    schedule(entry, "map", () => bindMapEvents(entry));
  }
}

function applyMapOptions(entry, spec, previous) {
  const map = entry.map;

  // By value: an inline style is parsed into a new object on every render.
  if (spec.style !== undefined && !sameValue(spec.style, previous.style)) {
    setStyle(entry, spec.style);
  }

  const camera = {};
  ["center", "zoom", "bearing", "pitch"].forEach((key) => {
    if (spec[key] !== undefined && !sameValue(spec[key], previous[key])) {
      camera[key] = spec[key];
    }
  });

  if (Object.keys(camera).length > 0) {
    // A declarative camera change is an assignment, not an animation. Callers
    // who want easing reach for HoloMap.API.fly_to/2 instead.
    //
    // The marker rides along on the events MapLibre emits for this move, so
    // `on_move_end` is not told about a move the application just made itself.
    // Without it, writing `zoom` from state echoes straight back into an
    // action — a feedback loop at best, and at worst an action arriving on
    // whichever page is mounted by the time it runs.
    map.jumpTo(camera, RECONCILED);
  }

  if (spec.maxBounds !== undefined && !sameValue(spec.maxBounds, previous.maxBounds)) {
    map.setMaxBounds(spec.maxBounds);
  }

  ["minZoom", "maxZoom", "minPitch", "maxPitch"].forEach((key) => {
    if (spec[key] !== undefined && !sameValue(spec[key], previous[key])) {
      map[`set${key[0].toUpperCase()}${key.slice(1)}`](spec[key]);
    }
  });
}

// Replaces the style, for the `style` prop and HoloMap.API.set_style/2.
//
// By default MapLibre diffs the new style against the map, which takes off
// everything this runtime declared (the new style does not carry it) and
// announces `style.load` only if anything changed. A style given by URL is
// fetched first, during which the old style keeps taking work, and a change
// the diff cannot make has it rebuild the style instead. `diff: false` takes
// one path every time: a new style that ends in `style.load`, where this
// runtime declares what it owns again. Until then style-scoped work and
// HoloMap.API calls wait, as they do for the first style.
function setStyle(entry, style, options) {
  entry.styleReady = false;
  entry.map.setStyle(style, { ...options, diff: false });
}

// --- entity lifecycle ------------------------------------------------------

function addEntity(entry, key) {
  const entity = entry.entities.get(key);

  if (!entity) {
    return;
  }

  switch (entity.kind) {
    case "image":
      addImage(entry, entity.id, entity);
      break;
    case "source":
      addSource(entry, entity.id, entity);
      break;
    case "layer":
      addLayer(entry, entity.id, entity);
      break;
    case "marker":
      addMarker(entry, key, entity);
      break;
    case "popup":
      addPopup(entry, key, entity);
      break;
    case "control":
      addControl(entry, key, entity);
      break;
    case "terrain":
      applyTerrain(entry, entity);
      break;
    case "sky":
      entry.map.setSky(entity.spec);
      break;
    default:
      warn(`unknown definition kind "${entity.kind}"`);
      return;
  }

  bindEvents(entry, key);
}

function updateEntity(entry, key, previous) {
  const entity = entry.entities.get(key);

  if (!entity) {
    return;
  }

  const previousSpec = previous.spec;

  switch (entity.kind) {
    case "image":
      updateImage(entry, entity.id, entity, previousSpec);
      break;
    case "source":
      updateSource(entry, entity.id, entity, previousSpec);
      break;
    case "layer":
      updateLayer(entry, entity.id, entity, previousSpec);
      break;
    case "marker": {
      const before = entity.object;
      updateMarker(entry, key, entity, previousSpec, previous.content);

      // A replaced marker is a new element and a new emitter, and the old
      // listeners left with the old ones. In-place updates keep them, so a
      // drag writing its position back on every frame rebinds nothing.
      if (entity.object !== before) {
        bindEvents(entry, key);
      }

      break;
    }
    case "popup":
      // Any popup put in place of the old one is bound inside updatePopup.
      updatePopup(entry, key, entity, previousSpec, previous.content);
      break;
    case "control":
      // Controls carry no updatable state worth diffing — replace outright.
      if (entity.object) {
        entry.map.removeControl(entity.object);
        entity.object = null;
      }

      addControl(entry, key, entity);
      break;
    case "terrain":
      applyTerrain(entry, entity);
      break;
    case "sky":
      entry.map.setSky(entity.spec);
      break;
  }
}

function removeEntity(entry, key, record = entry.entities.get(key)) {
  if (!record) {
    return;
  }

  unbindEvents(entry, key);

  switch (record.kind) {
    case "image":
      if (entry.map.hasImage(record.id)) {
        entry.map.removeImage(record.id);
      }

      break;
    case "source":
      removeSource(entry, record.id);
      break;
    case "layer":
      if (entry.map.getLayer(record.id)) {
        entry.map.removeLayer(record.id);
      }
      break;
    case "marker":
    case "popup":
      if (record.object) {
        record.object.remove();
      }
      break;
    case "control":
      if (record.object) {
        entry.map.removeControl(record.object);
        record.object = null;
      }
      break;
    case "terrain":
      entry.map.setTerrain(undefined);
      break;
    case "sky":
      // `undefined`, not `null`. MapLibre validates the argument before acting
      // on it, and rejects null with "sky: object expected, null found" — the
      // sky is still cleared, but a console error is logged every time a Sky
      // component is removed. `undefined` takes the same clearing path without
      // tripping the validator.
      entry.map.setSky(undefined);
      break;
  }
}

// --- images ----------------------------------------------------------------
//
// A symbol layer's `icon-image` names an image, it does not fetch one. The name
// has to already exist: either in the sprite the style ships, or registered
// here. Referencing one that is registered nowhere is a quiet failure —
// MapLibre emits `styleimagemissing` and draws nothing at all.
//
// Loading is asynchronous, and deliberately not ordered against the layers that
// use the image. MapLibre re-resolves a missing icon on later renders, so a
// layer declared before its image simply starts drawing once the image lands.

function addImage(entry, id, entity) {
  const { url, ...options } = entity.spec;

  if (!url) {
    warn(`image "${id}" has no url`);
    return;
  }

  // The image can still be registered when the re-declaration pass that
  // follows `style.load` reaches it: a new style starts without images, but
  // one MapLibre diffed into place keeps them. Adding it again would hit "an
  // image with this name already exists".
  if (entry.map.hasImage(id)) {
    return;
  }

  loadImage(entry, entity, url, (image) => {
    if (!entry.map.hasImage(id)) {
      entry.map.addImage(id, image, options);
    }
  });
}

function updateImage(entry, id, entity, previousSpec) {
  const { url, ...options } = entity.spec;
  const { url: previousUrl, ...previousOptions } = previousSpec;

  // Metadata — pixel ratio, sdf, the stretch regions — is fixed when the image
  // is registered, so a change there means registering it again.
  if (!sameValue(options, previousOptions)) {
    if (entry.map.hasImage(id)) {
      entry.map.removeImage(id);
    }

    addImage(entry, id, entity);
    return;
  }

  if (url !== previousUrl) {
    loadImage(entry, entity, url, (image) => {
      const registered = entry.map.getImage(id);

      // MapLibre's updateImage replaces only the pixels, and refuses an image
      // of another size. One of another size is registered again instead.
      if (
        registered &&
        registered.data.width === image.width &&
        registered.data.height === image.height
      ) {
        entry.map.updateImage(id, image);
        return;
      }

      if (registered) {
        entry.map.removeImage(id);
      }

      entry.map.addImage(id, image, options);
    });
  }
}

// Loads `url` for the image `entity` and hands the result to `apply`, if the
// image still wants it when it arrives. Responses come back in any order: a
// slow one for an earlier URL would replace the image of a later one, and one
// for a removed image would register it again with nothing left to remove it.
function loadImage(entry, entity, url, apply) {
  const load = {};
  entity.load = load;

  entry.map
    .loadImage(url)
    .then((result) => {
      // The map can be gone by the time a slow image arrives, and so can the
      // definition, or a later load can have started for it.
      if (!entry.disposed && entry.map && !entity.removed && entity.load === load) {
        apply(result.data);
      }
    })
    .catch((error) => {
      console.error(
        `[HoloMap:${entry.cid}] could not load image "${entity.id}" from ${url}`,
        error,
      );
    });
}

// --- sources ---------------------------------------------------------------

function addSource(entry, id, entity) {
  if (entry.map.getSource(id)) {
    return;
  }

  entry.map.addSource(id, entity.spec);

  // Any layer of this source not on the map was waiting for it: written above
  // it in the template, rendered while it was not, or taken off with it. So
  // can the terrain be.
  ownedLayersFor(entry, id).forEach((layer) => addLayer(entry, layer.id, layer));

  const terrain = terrainOf(entry);

  if (terrain && terrain.waiting && terrain.spec.source === id) {
    applyTerrain(entry, terrain);
  }
}

function updateSource(entry, id, entity, previousSpec) {
  const source = entry.map.getSource(id);

  if (!source) {
    addSource(entry, id, entity);
    return;
  }

  const onlyDataChanged =
    entity.spec.type === "geojson" &&
    sameValue({ ...entity.spec, data: null }, { ...previousSpec, data: null });

  if (onlyDataChanged) {
    source.setData(entity.spec.data);
    return;
  }

  if (entity.spec.type === "image" && typeof source.updateImage === "function") {
    source.updateImage({ url: entity.spec.url, coordinates: entity.spec.coordinates });
    return;
  }

  // Anything else is a structural change. MapLibre refuses to remove a source
  // that still has layers attached, so the dependent layers this runtime owns
  // come off first and go back on afterwards, in their declared order. The
  // terrain on it, whether HoloMap.Terrain's or the terrain control's, does
  // the same.
  const dependents = ownedLayersFor(entry, id);
  const terrain = detachTerrain(entry, id);

  dependents.forEach((layer) => {
    if (entry.map.getLayer(layer.id)) {
      entry.map.removeLayer(layer.id);
    }
  });

  entry.map.removeSource(id);
  addSource(entry, id, entity);

  if (terrain) {
    entry.map.setTerrain(terrain);
  }
}

function removeSource(entry, id) {
  const detached = detachTerrain(entry, id);
  const terrain = terrainOf(entry);

  if (detached && terrain && !terrain.removed && terrain.spec.source === id) {
    terrain.waiting = true;
    warn(
      `the source "${id}" that the terrain draws from was removed, so the map has no ` +
        `terrain until the source is rendered again`,
    );
  }

  ownedLayersFor(entry, id).forEach((layer) => {
    if (entry.map.getLayer(layer.id)) {
      entry.map.removeLayer(layer.id);
    }
  });

  if (entry.map.getSource(id)) {
    entry.map.removeSource(id);
  }
}

// The layer entities drawing from source `sourceId`, in declared order.
function ownedLayersFor(entry, sourceId) {
  return Array.from(entry.entities.values())
    .filter((entity) => entity.kind === "layer" && entity.spec.source === sourceId)
    .sort((a, b) => a.index - b.index);
}

// --- terrain ---------------------------------------------------------------
//
// MapLibre throws for terrain on a source it does not hold, and its terrain
// goes on drawing from the source object it was given after that source is
// removed or replaced. So terrain waits for its DEM source, as a layer does,
// and comes off before the source does.

function applyTerrain(entry, entity) {
  entity.waiting = !entry.map.getSource(entity.spec.source);

  if (!entity.waiting) {
    entry.map.setTerrain(entity.spec);
  } else if (entry.map.getTerrain()) {
    // The terrain on the map is not the one declared.
    entry.map.setTerrain(undefined);
  }
}

// The HoloMap.Terrain entity, if one is declared. A map has one terrain.
function terrainOf(entry) {
  return Array.from(entry.entities.values()).find((entity) => entity.kind === "terrain");
}

// Turns off the terrain drawing from source `id`, if any, and returns it.
function detachTerrain(entry, id) {
  const terrain = entry.map.getTerrain();

  if (!terrain || terrain.source !== id) {
    return null;
  }

  entry.map.setTerrain(undefined);
  return terrain;
}

// --- layers ----------------------------------------------------------------

function addLayer(entry, id, entity) {
  if (entry.map.getLayer(id)) {
    return;
  }

  // `beforeId` is not a layer key: layerBefore reads it to place the layer.
  const { beforeId: _beforeId, ...spec } = entity.spec;

  // MapLibre refuses a layer whose source it does not hold, and reports an
  // error. The layer waits instead, and adding the source adds it. A layer
  // whose source the style took over waits for the next style.
  if (
    typeof spec.source === "string" &&
    (!entry.map.getSource(spec.source) || sourceYielded(entry, entity))
  ) {
    return;
  }

  entry.map.addLayer({ id, ...spec }, layerBefore(entry, entity));

  if (entry.map.getLayer(id)) {
    placeLayersBeneath(entry, entity);
  }
}

function updateLayer(entry, id, entity, previousSpec) {
  if (!entry.map.getLayer(id)) {
    addLayer(entry, id, entity);
    return;
  }

  const structural = LAYER_IMMUTABLE_KEYS.some(
    (specKey) => !sameValue(entity.spec[specKey], previousSpec[specKey]),
  );

  if (structural) {
    entry.map.removeLayer(id);
    addLayer(entry, id, entity);
    return;
  }

  if (!sameValue(entity.spec.beforeId, previousSpec.beforeId)) {
    placeLayer(entry, entity);
  }

  diffProperties(entity.spec.paint, previousSpec.paint).forEach((property) => {
    entry.map.setPaintProperty(id, property, valueOf(entity.spec.paint, property));
  });

  diffProperties(entity.spec.layout, previousSpec.layout).forEach((property) => {
    entry.map.setLayoutProperty(id, property, valueOf(entity.spec.layout, property));
  });

  if (!sameValue(entity.spec.filter, previousSpec.filter)) {
    entry.map.setFilter(id, entity.spec.filter || null);
  }

  if (
    !sameValue(entity.spec.minzoom, previousSpec.minzoom) ||
    !sameValue(entity.spec.maxzoom, previousSpec.maxzoom)
  ) {
    entry.map.setLayerZoomRange(id, entity.spec.minzoom ?? 0, entity.spec.maxzoom ?? 24);
  }
}

// Returns every property name that differs between two paint/layout maps,
// including ones that were dropped (so they can be reset to their default).
function diffProperties(current = {}, previous = {}) {
  const names = new Set([...Object.keys(current || {}), ...Object.keys(previous || {})]);

  return Array.from(names).filter((name) => !sameValue((current || {})[name], (previous || {})[name]));
}

function valueOf(source, property) {
  const value = (source || {})[property];
  // `undefined` tells MapLibre to fall back to the specification default,
  // which is exactly what removing a property from the map should mean.
  return value === undefined ? undefined : value;
}

// --- layer order -----------------------------------------------------------
//
// Layers stack in template order, and `before_id` puts a layer beneath the one
// it names instead. MapLibre can only put a new layer on top or beneath a
// layer it already holds, so a layer reaching the map late (rendered
// conditionally, re-added by a structural change, or waiting for its source)
// is placed beneath the layer that follows it in the stack the template
// describes. Layers this runtime does not own keep their places.

// Layer ids bottom to top as the template stacks them: the layers this
// runtime does not own (the style's, a plugin's) where they are, then its own
// layers that are on the map, and `adding`, each placed in declared order as
// it would have been at first load. A `before_id` naming a layer declared
// further down the template takes effect once that layer is placed; one
// naming a layer not on the map is ignored until the layer appears.
function declaredStack(entry, adding) {
  const layers = Array.from(entry.entities.values())
    .filter(
      (entity) =>
        entity.kind === "layer" && (entity === adding || entry.map.getLayer(entity.id)),
    )
    .sort((a, b) => a.index - b.index);

  const owned = new Set(layers.map((layer) => layer.id));
  const stack = entry.map.getLayersOrder().filter((id) => !owned.has(id));
  const placed = new Set();
  const waiting = new Map();

  const place = (layer) => {
    if (placed.has(layer.id)) {
      return;
    }

    placed.add(layer.id);
    const at = stack.indexOf(layer.spec.beforeId);
    stack.splice(at === -1 ? stack.length : at, 0, layer.id);
    (waiting.get(layer.id) || []).forEach(place);
  };

  layers.forEach((layer) => {
    const anchor = layer.spec.beforeId;

    if (owned.has(anchor) && !placed.has(anchor)) {
      waiting.set(anchor, [...(waiting.get(anchor) || []), layer]);
    } else {
      place(layer);
    }
  });

  // Layers whose `before_id`s name each other in a cycle are still waiting.
  layers.forEach(place);

  return stack;
}

// The id of the layer `layer` belongs directly beneath, or undefined for the
// top of the stack.
function layerBefore(entry, layer) {
  const stack = declaredStack(entry, layer);
  return stack[stack.indexOf(layer.id) + 1];
}

// Moves a layer on the map to its place in the template unless it is there
// already, then the layers whose `before_id` names it.
function placeLayer(entry, layer, placed = new Set()) {
  if (placed.has(layer.id)) {
    return;
  }

  placed.add(layer.id);

  const before = layerBefore(entry, layer);
  const stack = entry.map.getLayersOrder();

  if (stack[stack.indexOf(layer.id) + 1] !== before) {
    entry.map.moveLayer(layer.id, before);
  }

  placeLayersBeneath(entry, layer, placed);
}

// Places the layers on the map whose `before_id` names `layer`: layers that
// were waiting for it, or that have to follow it. The last declared goes
// first, directly beneath `layer`, and each earlier one beneath the one after
// it.
function placeLayersBeneath(entry, layer, placed = new Set([layer.id])) {
  Array.from(entry.entities.values())
    .filter(
      (other) =>
        other.kind === "layer" &&
        other.spec.beforeId === layer.id &&
        entry.map.getLayer(other.id),
    )
    .sort((a, b) => b.index - a.index)
    .forEach((other) => placeLayer(entry, other, placed));
}

// --- markers and popups ----------------------------------------------------

function addMarker(entry, key, entity) {
  const { lngLat, popup, ...options } = entity.spec;
  const element = markerElement(entity);

  const marker = new MapLibreMarker(
    withClassNames({ ...options, ...(element ? { element } : {}) }),
  );
  marker.setLngLat(lngLat).addTo(entry.map);

  if (popup) {
    marker.setPopup(markerPopup(popup));
  }

  entity.object = marker;
}

function updateMarker(entry, key, entity, previousSpec, previousContent) {
  const marker = entity.object;
  const spec = entity.spec;

  if (!marker) {
    addMarker(entry, key, entity);
    return;
  }

  // Any of these changing means a new marker.
  const structural =
    entity.encoded.content !== previousContent ||
    MARKER_REBUILD_KEYS.some((name) => !sameValue(spec[name], previousSpec[name]));

  if (structural) {
    // MapLibre takes the marker's popup off the map with the marker, so a
    // popup the user has open is opened again on the new marker. It is a new
    // popup, which the new marker gives the offset that suits it, and which
    // is opened after the marker is on the map, as a click opens it: a click
    // on the marker then still closes it.
    const popup = marker.getPopup();
    const reopen = Boolean(popup && popup.isOpen());

    marker.remove();
    entity.object = null;
    addMarker(entry, key, entity);

    if (reopen) {
      entity.object.togglePopup();
    }

    return;
  }

  if (!sameValue(spec.lngLat, previousSpec.lngLat)) {
    marker.setLngLat(spec.lngLat);
  }

  if (!sameValue(spec.offset, previousSpec.offset)) {
    marker.setOffset(spec.offset || defaultMarkerOffset(entity));
  }

  if (!sameValue(spec.draggable, previousSpec.draggable)) {
    marker.setDraggable(Boolean(spec.draggable));
  }

  if (!sameValue(spec.rotation, previousSpec.rotation)) {
    marker.setRotation(spec.rotation || 0);
  }

  if (!sameValue(spec.opacity, previousSpec.opacity)) {
    // `undefined` resets MapLibre's opacity to its default.
    marker.setOpacity(spec.opacity);
  }

  if (
    !sameValue(spec.rotationAlignment, previousSpec.rotationAlignment) ||
    !sameValue(spec.pitchAlignment, previousSpec.pitchAlignment)
  ) {
    // Rotation first: an unset pitch alignment takes whatever the rotation
    // alignment is when it is set, as it does when MapLibre builds the marker.
    marker.setRotationAlignment(spec.rotationAlignment);
    marker.setPitchAlignment(spec.pitchAlignment);
  }

  if (!sameValue(spec.subpixelPositioning, previousSpec.subpixelPositioning)) {
    marker.setSubpixelPositioning(Boolean(spec.subpixelPositioning));
  }

  if (!sameValue(spec.popup, previousSpec.popup)) {
    updateMarkerPopup(marker, spec.popup, previousSpec.popup);
  }
}

// The offset MapLibre gives a marker built without one. Its default pin is
// lifted so that the tip, not the middle, is on the coordinate; an element of
// the marker's own, which slot content makes (see markerElement), is not moved.
function defaultMarkerOffset(entity) {
  return entity.encoded.content ? [0, 0] : [0, -14];
}

function markerPopup(popup) {
  return new MapLibrePopup(withClassNames(popup.options || {})).setHTML(popup.html || "");
}

// Only the content changing is an in-place setHTML. New options need a new
// popup, since MapLibre reads most of them only while building or opening
// one, and the replacement is reopened if the user had the old one open.
function updateMarkerPopup(marker, popup, previous) {
  const current = marker.getPopup();

  if (!popup) {
    marker.setPopup(null);
    return;
  }

  if (current && previous && sameValue(popup.options, previous.options)) {
    current.setHTML(popup.html || "");
    return;
  }

  const reopen = Boolean(current && current.isOpen());
  marker.setPopup(markerPopup(popup));

  if (reopen) {
    marker.togglePopup();
  }
}

// Markers with custom content get a *clone* of the slot markup, not the node
// Hologram rendered. MapLibre moves a marker's element into its own overlay
// container, and moving a node out from under the virtual DOM would corrupt
// the next patch. The cost is that Hologram event bindings inside the slot do
// not fire — use the marker's own `on_click` prop instead.
function markerElement(entity) {
  const content = entity.encoded.content;

  if (!content) {
    return null;
  }

  const element = document.createElement("div");
  element.className = ["holo-map-marker", ...classNames(entity.spec.className)].join(" ");
  element.innerHTML = content;

  return element;
}

function addPopup(entry, key, entity) {
  // Whatever was here goes first. Without this, any path that reaches addPopup
  // while an instance is still on the map leaves two identical popups stacked
  // on the same coordinate.
  if (entity.object) {
    entity.object.remove();
    entity.object = null;
  }

  const popup = buildPopup(entity);

  // MapLibre fires `open` from inside addTo, so the listeners go on first.
  // Bound any later, `on_open` would never fire.
  entity.object = popup;
  bindEvents(entry, key);
  popup.addTo(entry.map);
}

function buildPopup(entity) {
  const { lngLat, html, ...options } = entity.spec;
  const popup = new MapLibrePopup(withClassNames(options));

  popup.setLngLat(lngLat);
  popup.setHTML(popupHTML(entity.spec, entity.encoded.content));

  return popup;
}

function updatePopup(entry, key, entity, previousSpec, previousContent) {
  const popup = entity.object;
  const spec = entity.spec;

  // MapLibre closes a popup on its own for reasons this runtime never hears
  // about: the close button, a click on the map, a camera move. The definition
  // still says the popup should be there, so a changed declaration re-asserts
  // it rather than quietly writing to something that is no longer on screen.
  if (!popup || !popup.isOpen()) {
    addPopup(entry, key, entity);
    return;
  }

  if (POPUP_REBUILD_KEYS.some((name) => !sameValue(spec[name], previousSpec[name]))) {
    // Swapped for a popup built with the new options. The declaration says
    // open throughout, so this is neither a close nor an open: the listeners
    // come off before and go back on after, and neither event is reported.
    unbindEvents(entry, key);
    popup.remove();
    entity.object = buildPopup(entity);
    entity.object.addTo(entry.map);
    bindEvents(entry, key);
    return;
  }

  popup.setLngLat(spec.lngLat);

  // setHTML rebuilds the content, losing what the user scrolled or selected
  // in it, and with `focus_after_open` moves focus back into it. A popup that
  // follows a moving feature would do so on every move.
  const html = popupHTML(spec, entity.encoded.content);

  if (html !== popupHTML(previousSpec, previousContent)) {
    popup.setHTML(html);
  }

  if (!sameValue(spec.maxWidth, previousSpec.maxWidth)) {
    // MapLibre's own default. Given nothing, it leaves the old width in place.
    popup.setMaxWidth(spec.maxWidth || "240px");
  }

  if (!sameValue(spec.offset, previousSpec.offset)) {
    popup.setOffset(spec.offset);
  }

  if (!sameValue(spec.className, previousSpec.className)) {
    classNames(previousSpec.className).forEach((name) => popup.removeClassName(name));
    classNames(spec.className).forEach((name) => popup.addClassName(name));
  }

  if (!sameValue(spec.subpixelPositioning, previousSpec.subpixelPositioning)) {
    popup.setSubpixelPositioning(Boolean(spec.subpixelPositioning));
  }
}

// MapLibre's class setters take one name at a time.
function classNames(className) {
  return (className || "").split(/\s+/).filter(Boolean);
}

// Marker or popup options with their `className` as MapLibre reads it while
// building the object: split on single spaces, every piece handed to
// classList.add, which throws for an empty one. Spaces around the names or
// several in a row would keep the marker or popup off the map.
function withClassNames(options) {
  if (options.className === undefined) {
    return options;
  }

  return { ...options, className: classNames(options.className).join(" ") };
}

// What a popup shows: its `html` prop, or else its slot content.
function popupHTML(spec, content) {
  return spec.html || content || "";
}

// --- controls --------------------------------------------------------------

function addControl(entry, key, entity) {
  const { control, position, ...options } = entity.spec;
  const Constructor = CONTROL_CLASSES[control];

  if (!Constructor) {
    warn(`unknown control "${control}"`);
    return;
  }

  const corner = position || "top-right";
  const controlInstance = new Constructor(options);
  entry.map.addControl(controlInstance, corner);
  entity.object = controlInstance;
  placeControl(entry, entity, corner);
}

// MapLibre adds a control at the end of its corner away from the map's edge:
// last in a top corner, first in a bottom one. A control that reaches the map
// after others declared below it in the template, because it was rendered
// conditionally or an update replaced it, is moved back next to the nearest of
// them, so the corner keeps the declared order. Moving its element, rather
// than removing and adding the controls after it, leaves their state alone: a
// geolocate control that is following the user goes on following.
function placeControl(entry, entity, corner) {
  const cornerElement = entry.container.querySelector(`.maplibregl-ctrl-${corner}`);

  if (!cornerElement) {
    return;
  }

  const bottom = corner.startsWith("bottom");
  entity.controlElement = bottom ? cornerElement.firstElementChild : cornerElement.lastElementChild;

  const [next] = Array.from(entry.entities.values())
    .filter(
      (other) =>
        other.kind === "control" &&
        other.index > entity.index &&
        other.controlElement &&
        other.controlElement.parentNode === cornerElement,
    )
    .sort((a, b) => a.index - b.index);

  if (next) {
    // Declared order runs away from the edge: down a top corner, up a bottom
    // one.
    const reference = bottom ? next.controlElement.nextSibling : next.controlElement;
    cornerElement.insertBefore(entity.controlElement, reference);
  }
}

// --- events ----------------------------------------------------------------

function bindMapEvents(entry) {
  unbindEvents(entry, "__map__");

  Object.entries(entry.mapEvents || {}).forEach(([name, handler]) => {
    const listener = (event) => {
      if (event && event.holoMapReconciled) {
        return;
      }

      if (reportedByMarker(event)) {
        return;
      }

      const payload = mapPayload(entry, event);

      if (name === "error") {
        payload.error = errorPayload(event);
      }

      dispatch(entry, handler, payload);
    };
    entry.map.on(name, listener);
    entry.listeners.push({ key: "__map__", name, layer: null, listener });
  });
}

function bindEvents(entry, key) {
  const entity = entry.entities.get(key);

  if (!entity) {
    return;
  }

  unbindEvents(entry, key);

  const events = entity.events || {};

  if (entity.kind === "layer") {
    Object.entries(events).forEach(([name, handler]) => {
      const listener = (event) => {
        if (reportedByMarker(event)) {
          return;
        }

        // Read now: MapLibre takes the features off the event once the
        // listener returns.
        const payload = layerPayload(entry, entity.id, event);

        // MapLibre runs the map's `click` listeners in the order they were
        // added, and a popup that opened after this layer's listener closes
        // after it: a click would select a feature before the popup's
        // `on_close` cleared the selection.
        if (name === "click") {
          dispatchAfterClick(entry, handler, payload);
        } else {
          dispatch(entry, handler, payload);
        }
      };

      entry.map.on(name, entity.id, listener);
      entry.listeners.push({ key, name, layer: entity.id, listener });
    });

    return;
  }

  if (entity.kind === "popup" && entity.object) {
    Object.entries(events).forEach(([name, handler]) => {
      const listener = () => dispatch(entry, handler, {});
      entity.object.on(name, listener);
      entry.listeners.push({ key, name, emitter: entity.object, listener });
    });

    return;
  }

  if (entity.kind === "marker" && entity.object) {
    Object.entries(events).forEach(([name, handler]) => {
      const element = entity.object.getElement();

      if (name === "dragend" || name === "drag" || name === "dragstart") {
        const listener = () =>
          dispatch(entry, handler, { lng_lat: toLngLat(entity.object.getLngLat()) });
        entity.object.on(name, listener);
        entry.listeners.push({ key, name, emitter: entity.object, listener });
        return;
      }

      const listener = (event) => {
        // Marked, not stopped. MapLibre makes the map's own `click` from this
        // DOM event once it bubbles up to the canvas container, and opens the
        // marker's popup and closes `close_on_click` popups from that map
        // event. The mark keeps the map's and the layers' handlers from
        // reporting this click a second time.
        event.holoMapMarker = true;

        dispatchAfterClick(entry, handler, { lng_lat: toLngLat(entity.object.getLngLat()) });
      };

      element.addEventListener(name, listener);
      entry.listeners.push({ key, name, element, listener });
    });
  }
}

// Reports a click on a marker or a layer once the click has finished
// propagating, so after the `on_close` of any popup it closed. Hologram runs
// actions in the order they are dispatched, and a popup that clears the
// selection on close would otherwise undo the selection this click makes. A
// microtask is not late enough: the browser runs microtasks between the
// listeners of a user's click. A timer is a task of its own, and runs after
// the whole dispatch.
function dispatchAfterClick(entry, handler, payload) {
  setTimeout(() => dispatch(entry, handler, payload), 0);
}

// Whether a map or layer event comes from a DOM event that a marker's own
// handler has already reported.
function reportedByMarker(event) {
  return Boolean(event && event.originalEvent && event.originalEvent.holoMapMarker);
}

function unbindEvents(entry, key) {
  const kept = [];

  entry.listeners.forEach((record) => {
    if (record.key !== key) {
      kept.push(record);
      return;
    }

    if (record.element) {
      record.element.removeEventListener(record.name, record.listener);
    } else if (record.emitter) {
      record.emitter.off(record.name, record.listener);
    } else if (record.layer) {
      entry.map.off(record.name, record.layer, record.listener);
    } else {
      entry.map.off(record.name, record.listener);
    }
  });

  entry.listeners = kept;
}

function dispatch(entry, handler, payload) {
  if (!handler || !handler.action) {
    return;
  }

  // The decisive guard against an event outliving its map.
  //
  // Hologram replaces the whole DOM on navigation, and MapLibre keeps emitting
  // for a beat afterwards — a detaching container alone produces a `moveend`.
  // Dispatching that reaches the action handler of whichever page is mounted
  // *now*, which raises FunctionClauseError on a page that never asked for it.
  // Nothing downstream can tell such an event apart from a real one, so it is
  // stopped here.
  if (entry.disposed || !entry.container || !entry.container.isConnected) {
    return;
  }

  const hologram = window.Hologram;

  if (!hologram || typeof hologram.dispatchAction !== "function") {
    warn("Hologram.dispatchAction is unavailable — dropping map event");
    return;
  }

  // Runtime data wins over static params: a caller who set `params: %{id: 1}`
  // still gets the real feature id when the event carries one.
  hologram.dispatchAction(handler.action, handler.target || "page", {
    ...(handler.params || {}),
    ...payload,
  });
}

function mapPayload(entry, event) {
  const center = entry.map.getCenter();
  const bounds = entry.map.getBounds();

  const payload = {
    center: [center.lng, center.lat],
    zoom: entry.map.getZoom(),
    bearing: entry.map.getBearing(),
    pitch: entry.map.getPitch(),
    bounds: [
      [bounds.getWest(), bounds.getSouth()],
      [bounds.getEast(), bounds.getNorth()],
    ],
  };

  if (event && event.lngLat) {
    payload.lng_lat = toLngLat(event.lngLat);
    payload.point = [event.point.x, event.point.y];
  }

  return payload;
}

// What an `error` event says failed. MapLibre hands over an Error, for a
// failed request one carrying the HTTP status and URL, and for a source's
// error the source id and possibly the tile. Error and tile objects cannot
// cross into Elixir, so only those plain values are carried over.
function errorPayload(event) {
  const error = event && event.error;
  const message = error && typeof error === "object" ? error.message : error;
  const payload = { message: message === undefined || message === null ? "" : String(message) };

  if (error && typeof error.status === "number") {
    payload.status = error.status;
  }

  if (error && typeof error.url === "string") {
    payload.url = error.url;
  }

  if (event && typeof event.sourceId === "string") {
    payload.source_id = event.sourceId;
  }

  return payload;
}

function layerPayload(entry, layerKey, event) {
  return {
    layer: layerKey,
    lng_lat: toLngLat(event.lngLat),
    point: [event.point.x, event.point.y],
    features: (event.features || []).map(serializeFeature),
  };
}

// MapLibre feature objects hold back-references to their source and tile,
// which cannot cross into Elixir. Only the parts a handler can act on are
// carried over.
function serializeFeature(feature) {
  return {
    id: feature.id === undefined ? null : feature.id,
    source: feature.source || null,
    source_layer: feature.sourceLayer || null,
    properties: { ...(feature.properties || {}) },
    geometry: feature.geometry || null,
  };
}

function toLngLat(lngLat) {
  return [lngLat.lng, lngLat.lat];
}

// --- plumbing --------------------------------------------------------------

// Runs `fn` now, or queues it until the style is ready when it is style-scoped
// work. `kind` is the definition kind the work belongs to; anything outside
// STYLE_SCOPED runs immediately.
function schedule(entry, kind, fn) {
  if (entry.styleReady || !STYLE_SCOPED.has(kind)) {
    runGuarded(entry, fn);
  } else {
    entry.pending.push(fn);
  }
}

// Runs the queued work in order while the style takes it. Work that changes
// the style ends the run, and the rest waits for the next `style.load`.
function flush(entry) {
  while (entry.styleReady && entry.pending.length > 0) {
    runGuarded(entry, entry.pending.shift());
  }
}

// Re-adds every style-scoped object this runtime owns, in declared order, after
// a style swap has wiped them from MapLibre.
function redeclareStyleScoped(entry) {
  const entities = Array.from(entry.entities.entries())
    .filter(([, entity]) => STYLE_SCOPED.has(entity.kind))
    .sort((a, b) => a[1].index - b[1].index);

  // A style swap wiped everything this runtime owned, so anything answering
  // to one of its ids now belongs to the incoming style. That is decided
  // before anything is added back: re-adding a source re-adds its layers.
  const taken = new Set(
    entities
      .filter(
        ([, entity]) =>
          (entity.kind === "layer" && entry.map.getLayer(entity.id)) ||
          (entity.kind === "source" && entry.map.getSource(entity.id)),
      )
      .map(([key]) => key),
  );

  entities.forEach(([key, entity]) => {
    // A source the style took over keeps its layers off the map as well
    // (see addLayer). On the style's source they would draw the style's
    // data, and a vector source refuses them outright.
    entity.yielded = entity.kind === "source" && taken.has(key);
  });

  entities.forEach(([key, entity]) => {
    // Adding is skipped for an id that already exists, which would otherwise
    // leave the component silently driving someone else's source or layer.
    if (taken.has(key)) {
      const layers = entity.yielded ? ownedLayersFor(entry, entity.id) : [];
      const left = layers.length > 0 ? `, and its layers ${quoted(layers)} stay off the map` : "";

      warn(
        `the new style already defines a ${entity.kind} called "${entity.id}", so the ` +
          `component of that id has nothing to add${left}. Give it an id the style does not use.`,
      );
      return;
    }

    runGuarded(entry, () => addEntity(entry, key));
  });
}

// Whether `layer` draws from a source of this runtime that the style took over.
function sourceYielded(entry, layer) {
  const source = entry.entities.get(keyFor("source", layer.spec.source));
  return Boolean(source && source.yielded);
}

function quoted(entities) {
  return entities.map((entity) => `"${entity.id}"`).join(", ");
}

// One failing definition must not take the rest of the map with it. A bad
// paint expression should leave a console error and a map missing one layer,
// not a blank page.
function runGuarded(entry, fn) {
  try {
    fn();
  } catch (error) {
    console.error(`[HoloMap:${entry.cid}]`, error);
  }
}

function dispose(entry) {
  if (entry.disposed) {
    return;
  }

  entry.disposed = true;

  if (entry.observer) {
    entry.observer.disconnect();
  }

  entry.entities.forEach((entity) => {
    if (entity.object && typeof entity.object.remove === "function") {
      try {
        entity.object.remove();
      } catch (error) {
        // The map is going away regardless.
      }
    }
  });

  entry.entities.clear();

  // Detaching has to go through map.off / removeEventListener. Emptying the
  // bookkeeping array only loses track of the listeners; it leaves them
  // attached and firing, which is how a torn-down map went on dispatching.
  detachAllListeners(entry);

  if (entry.map) {
    entry.map.remove();
    entry.map = null;
  }

  if (registry.get(entry.cid) === entry) {
    registry.delete(entry.cid);
  }
}

// Points MapLibre at its own worker file.
//
// MapLibre builds its tile-parsing worker from a blob that imports
// `./maplibre-gl-worker.mjs` resolved against `import.meta.url`. That works
// when the library is loaded as its own module, but Hologram bundles it into a
// page bundle under `/hologram/`, so the resolved URL points at a file that is
// not there. The import fails inside the worker, where nothing surfaces it: the
// style is fetched, the map paints its background, and no tile is ever parsed —
// a permanently empty map with a clean console.
//
// Setting the URL explicitly is MapLibre's supported answer. It is global
// rather than per-map, so it is set once, before the first map is constructed.
let workerConfigured = false;

function configureWorker(workerUrl) {
  if (workerConfigured || !workerUrl) {
    return;
  }

  workerConfigured = true;
  setWorkerUrl(workerUrl);
}

// A map's container is stale once it has left the document — or once Hologram
// has morphed it into a *different* map's container.
//
// The second case is the one that is easy to miss. Navigating between two
// pages that each hold a map patches the outgoing `<div id="hm--basic">` into
// `<div id="hm--cities">` in place: the node never leaves the document, so
// `isConnected` stays true and a liveness check built on it alone would let
// the old MapLibre instance live forever. Its canvas is a JS-managed child, so
// Hologram faithfully preserves it, and the new map is constructed alongside
// it — one leaked WebGL context per navigation, against a browser limit of
// roughly sixteen.
function isStale(entry) {
  return !entry.container.isConnected || entry.container.id !== containerId(entry.cid);
}

function detachAllListeners(entry) {
  entry.listeners.forEach((record) => {
    try {
      if (record.element) {
        record.element.removeEventListener(record.name, record.listener);
      } else if (record.emitter) {
        record.emitter.off(record.name, record.listener);
      } else if (record.layer) {
        entry.map.off(record.name, record.layer, record.listener);
      } else {
        entry.map.off(record.name, record.listener);
      }
    } catch (error) {
      // The map is being torn down; a listener that cannot be detached is
      // going away with it.
    }
  });

  entry.listeners = [];
}

function clearOrphanedCanvas(container) {
  container.querySelectorAll(".maplibregl-canvas-container, .maplibregl-control-container")
    .forEach((node) => node.remove());
}

function containerId(cid) {
  return `hm--${cid}`;
}

function defsId(cid) {
  return `hm--${cid}--defs`;
}

function parseJSON(raw, fallback) {
  try {
    return JSON.parse(raw);
  } catch (error) {
    console.error("[HoloMap] malformed specification attribute", raw, error);
    return fallback;
  }
}

function sameValue(a, b) {
  if (a === b) {
    return true;
  }

  if (a === undefined || b === undefined || a === null || b === null) {
    return false;
  }

  if (typeof a !== "object" || typeof b !== "object") {
    return false;
  }

  return JSON.stringify(a) === JSON.stringify(b);
}

function warn(message) {
  console.warn(`[HoloMap] ${message}`);
}
