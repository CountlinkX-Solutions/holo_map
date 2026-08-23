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
    this.styleReady = false;
    // Style-scoped work queued while MapLibre is still parsing the style. A
    // page renders its whole component tree before the first byte of style
    // arrives, so the first reconcile always lands early.
    this.pending = [];
    // key -> { kind, spec, events, encoded, object }
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
  const container = document.getElementById(containerId(cid));
  const defs = document.getElementById(defsId(cid));

  if (!container || !defs) {
    // The action fired before the DOM settled. Hologram patches synchronously,
    // so one frame is enough; retrying rather than throwing keeps a slow first
    // paint from turning into a hard error.
    requestAnimationFrame(() => boot(cid));
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

  const mapDef = readMapDef(defs, cid);
  const { workerUrl, ...mapOptions } = mapDef ? mapDef.spec : {};

  configureWorker(workerUrl);

  entry.map = new MapLibreMap({ ...mapOptions, container });

  // `style.load` is the point MapLibre will accept addSource/addLayer. The
  // `load` event is later and stricter — it also waits for the first complete
  // render, which never arrives if a tile request hangs, and gating on it
  // meant a map that renders but stays permanently empty.
  entry.map.on("style.load", () => {
    const first = !entry.styleReady;
    entry.styleReady = true;

    if (first) {
      flush(entry);
    } else {
      // A style swap discards every source and layer MapLibre knew about, so
      // the ones this runtime owns have to be declared again from scratch.
      redeclareStyleScoped(entry);
    }

    reconcile(entry);
  });

  startObserver(entry);
  ensureLivenessObserver();
  reconcile(entry);
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
// call if the style has not finished loading.
export function invoke(cid, method, args) {
  const entry = registry.get(cid);

  if (!entry || entry.disposed) {
    warn(`no map is registered for cid "${cid}" — ignoring ${method}()`);
    return;
  }

  schedule(entry, "layer", () => {
    const target = entry.map;

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

  desired.forEach((def, index) => {
    if (def.kind === "map") {
      applyMapDef(entry, def);
      return;
    }

    seen.add(def.key);
    const previous = entry.entities.get(def.key);

    if (!previous) {
      entry.entities.set(def.key, {
        kind: def.kind,
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

    if (previous.kind !== def.kind) {
      // A key was reused for a different kind of object. Treat it as a
      // replacement rather than trying to morph one into the other.
      schedule(entry, previous.kind, () => removeEntity(entry, def.key));
      entry.entities.set(def.key, {
        kind: def.kind,
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
    previous.index = index;

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

  Array.from(entry.entities.keys()).forEach((key) => {
    if (!seen.has(key)) {
      const removed = entry.entities.get(key);
      entry.entities.delete(key);
      schedule(entry, removed.kind, () => removeEntity(entry, key, removed));
    }
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

  return {
    kind,
    mapCid: element.getAttribute("data-hm-map"),
    key: element.getAttribute("data-hm-key") || kind,
    spec: parseJSON(rawSpec, {}),
    events: parseJSON(rawEvents, {}),
    encoded: { spec: rawSpec, events: rawEvents, content },
    element,
  };
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

  if (spec.style !== previous.style && spec.style !== undefined) {
    map.setStyle(spec.style);
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

// --- entity lifecycle ------------------------------------------------------

function addEntity(entry, key) {
  const entity = entry.entities.get(key);

  if (!entity) {
    return;
  }

  switch (entity.kind) {
    case "image":
      addImage(entry, key, entity);
      break;
    case "source":
      addSource(entry, key, entity);
      break;
    case "layer":
      addLayer(entry, key, entity);
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
      entry.map.setTerrain(entity.spec);
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
      updateImage(entry, key, entity, previousSpec);
      break;
    case "source":
      updateSource(entry, key, entity, previousSpec);
      break;
    case "layer":
      updateLayer(entry, key, entity, previousSpec);
      break;
    case "marker":
      updateMarker(entry, key, entity, previousSpec, previous.content);
      break;
    case "popup":
      updatePopup(entry, key, entity);
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
      entry.map.setTerrain(entity.spec);
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
      if (entry.map.hasImage(key)) {
        entry.map.removeImage(key);
      }

      break;
    case "source":
      removeSource(entry, key);
      break;
    case "layer":
      if (entry.map.getLayer(key)) {
        entry.map.removeLayer(key);
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

function addImage(entry, key, entity) {
  const { url, ...options } = entity.spec;

  if (!url) {
    warn(`image "${key}" has no url`);
    return;
  }

  // Registered images survive a style swap, so the re-declaration pass that
  // follows `style.load` would otherwise hit "an image with this name already
  // exists".
  if (entry.map.hasImage(key)) {
    return;
  }

  loadImage(entry, key, url, (image) => {
    if (!entry.map.hasImage(key)) {
      entry.map.addImage(key, image, options);
    }
  });
}

function updateImage(entry, key, entity, previousSpec) {
  const { url, ...options } = entity.spec;
  const { url: previousUrl, ...previousOptions } = previousSpec;

  // Metadata — pixel ratio, sdf, the stretch regions — is fixed when the image
  // is registered, so a change there means registering it again.
  if (!sameValue(options, previousOptions)) {
    if (entry.map.hasImage(key)) {
      entry.map.removeImage(key);
    }

    addImage(entry, key, entity);
    return;
  }

  if (url !== previousUrl) {
    loadImage(entry, key, url, (image) => {
      if (entry.map.hasImage(key)) {
        entry.map.updateImage(key, image);
      } else {
        entry.map.addImage(key, image, options);
      }
    });
  }
}

function loadImage(entry, key, url, apply) {
  entry.map
    .loadImage(url)
    .then((result) => {
      // The map can be gone by the time a slow image arrives.
      if (!entry.disposed && entry.map) {
        apply(result.data);
      }
    })
    .catch((error) => {
      console.error(`[HoloMap:${entry.cid}] could not load image "${key}" from ${url}`, error);
    });
}

// --- sources ---------------------------------------------------------------

function addSource(entry, key, entity) {
  if (entry.map.getSource(key)) {
    return;
  }

  entry.map.addSource(key, entity.spec);
}

function updateSource(entry, key, entity, previousSpec) {
  const source = entry.map.getSource(key);

  if (!source) {
    addSource(entry, key, entity);
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
  // come off first and go back on afterwards, in their declared order.
  const dependents = ownedLayersFor(entry, key);

  dependents.forEach(([layerKey]) => {
    if (entry.map.getLayer(layerKey)) {
      entry.map.removeLayer(layerKey);
    }
  });

  entry.map.removeSource(key);
  entry.map.addSource(key, entity.spec);

  dependents.forEach(([layerKey, layerEntity]) => addLayer(entry, layerKey, layerEntity));
}

function removeSource(entry, key) {
  ownedLayersFor(entry, key).forEach(([layerKey]) => {
    if (entry.map.getLayer(layerKey)) {
      entry.map.removeLayer(layerKey);
    }
  });

  if (entry.map.getSource(key)) {
    entry.map.removeSource(key);
  }
}

function ownedLayersFor(entry, sourceKey) {
  return Array.from(entry.entities.entries())
    .filter(([, entity]) => entity.kind === "layer" && entity.spec.source === sourceKey)
    .sort((a, b) => a[1].index - b[1].index);
}

// --- layers ----------------------------------------------------------------

function addLayer(entry, key, entity) {
  if (entry.map.getLayer(key)) {
    return;
  }

  const { beforeId, ...spec } = entity.spec;
  const before = beforeId && entry.map.getLayer(beforeId) ? beforeId : undefined;

  entry.map.addLayer({ id: key, ...spec }, before);
}

function updateLayer(entry, key, entity, previousSpec) {
  if (!entry.map.getLayer(key)) {
    addLayer(entry, key, entity);
    return;
  }

  const structural = LAYER_IMMUTABLE_KEYS.some(
    (specKey) => !sameValue(entity.spec[specKey], previousSpec[specKey]),
  );

  if (structural) {
    entry.map.removeLayer(key);
    addLayer(entry, key, entity);
    return;
  }

  diffProperties(entity.spec.paint, previousSpec.paint).forEach((property) => {
    entry.map.setPaintProperty(key, property, valueOf(entity.spec.paint, property));
  });

  diffProperties(entity.spec.layout, previousSpec.layout).forEach((property) => {
    entry.map.setLayoutProperty(key, property, valueOf(entity.spec.layout, property));
  });

  if (!sameValue(entity.spec.filter, previousSpec.filter)) {
    entry.map.setFilter(key, entity.spec.filter || null);
  }

  if (
    !sameValue(entity.spec.minzoom, previousSpec.minzoom) ||
    !sameValue(entity.spec.maxzoom, previousSpec.maxzoom)
  ) {
    entry.map.setLayerZoomRange(key, entity.spec.minzoom ?? 0, entity.spec.maxzoom ?? 24);
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

// --- markers and popups ----------------------------------------------------

function addMarker(entry, key, entity) {
  const { lngLat, popup, ...options } = entity.spec;
  const element = markerElement(entity);

  const marker = new MapLibreMarker({ ...options, ...(element ? { element } : {}) });
  marker.setLngLat(lngLat).addTo(entry.map);

  if (popup) {
    marker.setPopup(new MapLibrePopup(popup.options || {}).setHTML(popup.html || ""));
  }

  entity.object = marker;
}

function updateMarker(entry, key, entity, previousSpec, previousContent) {
  const marker = entity.object;

  if (!marker) {
    addMarker(entry, key, entity);
    return;
  }

  // MapLibre fixes a marker's element at construction time, and `color` and
  // `scale` only shape the default pin it builds there. Any of those changing
  // means a new marker.
  const structural =
    entity.encoded.content !== previousContent ||
    !sameValue(entity.spec.color, previousSpec.color) ||
    !sameValue(entity.spec.scale, previousSpec.scale) ||
    !sameValue(entity.spec.className, previousSpec.className);

  if (structural) {
    marker.remove();
    entity.object = null;
    addMarker(entry, key, entity);
    return;
  }

  if (!sameValue(entity.spec.lngLat, previousSpec.lngLat)) {
    marker.setLngLat(entity.spec.lngLat);
  }

  if (!sameValue(entity.spec.offset, previousSpec.offset)) {
    marker.setOffset(entity.spec.offset || [0, 0]);
  }

  if (!sameValue(entity.spec.draggable, previousSpec.draggable)) {
    marker.setDraggable(Boolean(entity.spec.draggable));
  }

  if (!sameValue(entity.spec.rotation, previousSpec.rotation)) {
    marker.setRotation(entity.spec.rotation || 0);
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
  element.className = ["holo-map-marker", entity.spec.className].filter(Boolean).join(" ");
  element.innerHTML = content;

  return element;
}

function addPopup(entry, key, entity) {
  const { lngLat, html, ...options } = entity.spec;
  const popup = new MapLibrePopup(options);

  popup.setLngLat(lngLat);
  popup.setHTML(html || popupContent(entity));
  popup.addTo(entry.map);

  entity.object = popup;
}

function updatePopup(entry, key, entity) {
  const popup = entity.object;

  if (!popup) {
    addPopup(entry, key, entity);
    return;
  }

  popup.setLngLat(entity.spec.lngLat);
  popup.setHTML(entity.spec.html || popupContent(entity));
}

function popupContent(entity) {
  return entity.encoded.content || "";
}

// --- controls --------------------------------------------------------------

function addControl(entry, key, entity) {
  const { control, position, ...options } = entity.spec;
  const Constructor = CONTROL_CLASSES[control];

  if (!Constructor) {
    warn(`unknown control "${control}"`);
    return;
  }

  const controlInstance = new Constructor(options);
  entry.map.addControl(controlInstance, position || "top-right");
  entity.object = controlInstance;
}

// --- events ----------------------------------------------------------------

function bindMapEvents(entry) {
  unbindEvents(entry, "__map__");

  Object.entries(entry.mapEvents || {}).forEach(([name, handler]) => {
    const listener = (event) => {
      if (event && event.holoMapReconciled) {
        return;
      }

      dispatch(entry, handler, mapPayload(entry, event));
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
      const listener = (event) => dispatch(entry, handler, layerPayload(entry, key, event));
      entry.map.on(name, key, listener);
      entry.listeners.push({ key, name, layer: key, listener });
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
        entry.listeners.push({ key, name, marker: entity.object, listener });
        return;
      }

      const listener = (event) => {
        event.stopPropagation();
        dispatch(entry, handler, { lng_lat: toLngLat(entity.object.getLngLat()) });
      };

      element.addEventListener(name, listener);
      entry.listeners.push({ key, name, element, listener });
    });
  }
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
    } else if (record.marker) {
      record.marker.off(record.name, record.listener);
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

function flush(entry) {
  const queued = entry.pending;
  entry.pending = [];
  queued.forEach((fn) => runGuarded(entry, fn));
}

// Re-adds every style-scoped object this runtime owns, in declared order, after
// a style swap has wiped them from MapLibre.
function redeclareStyleScoped(entry) {
  Array.from(entry.entities.entries())
    .filter(([, entity]) => STYLE_SCOPED.has(entity.kind))
    .sort((a, b) => a[1].index - b[1].index)
    .forEach(([key]) => runGuarded(entry, () => addEntity(entry, key)));
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
      } else if (record.marker) {
        record.marker.off(record.name, record.listener);
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
