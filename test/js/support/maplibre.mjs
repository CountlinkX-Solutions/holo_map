// Stands in for maplibre-gl in the runtime unit tests.
//
// Every class records the calls the runtime makes and keeps just the state
// those calls imply (the sources, the layer stack, controls, markers and
// popups on the map), so a test can assert both on what was asked and on what
// a real map would now hold. Nothing here renders, fetches or parses.
//
// MapLibre's events are driven by hand: `map.loadStyle()` plays a style
// arriving, which wipes the style-scoped state and emits `style.load`, and
// `fire()` emits any other event.

// Every Map constructed, oldest first.
export const maps = [];

export let workerUrl = null;

export function setWorkerUrl(url) {
  workerUrl = url;
}

class Evented {
  constructor() {
    this.handlers = [];
  }

  // Mirrors MapLibre's two signatures: on(type, listener) and, for layer
  // events, on(type, layerId, listener).
  on(type, ...rest) {
    const [layer, listener] = rest.length === 2 ? rest : [null, rest[0]];
    this.handlers.push({ type, layer, listener });
    return this;
  }

  off(type, ...rest) {
    const [layer, listener] = rest.length === 2 ? rest : [null, rest[0]];

    this.handlers = this.handlers.filter(
      (handler) =>
        handler.type !== type || handler.layer !== layer || handler.listener !== listener,
    );

    return this;
  }

  fire(type, event = {}, layer = null) {
    this.handlers
      .filter((handler) => handler.type === type && handler.layer === layer)
      .forEach((handler) => handler.listener(event));
  }

  listenerCount(type, layer = null) {
    return this.handlers.filter((handler) => handler.type === type && handler.layer === layer)
      .length;
  }
}

class FakeMap extends Evented {
  constructor(options) {
    super();
    this.options = options;
    this.calls = [];
    this.sources = new Map();
    this.layers = [];
    this.controls = [];
    this.markers = new Set();
    this.popups = new Set();
    this.camera = { center: { lng: 0, lat: 0 }, zoom: 0, bearing: 0, pitch: 0 };
    this.removed = false;
    maps.push(this);
  }

  record(name, ...args) {
    this.calls.push([name, ...args]);
  }

  // The calls made to `name`, as argument lists.
  callsTo(name) {
    return this.calls.filter(([called]) => called === name).map(([, ...args]) => args);
  }

  // Plays a style arriving: whatever the previous style held is gone, the
  // new style's own sources and layers are in place, and `style.load` fires.
  loadStyle({ sources = {}, layers = [] } = {}) {
    this.sources = new Map(
      Object.entries(sources).map(([id, spec]) => [id, this.sourceObject(id, spec)]),
    );
    this.layers = layers.map((layer) => ({ ...layer }));
    this.fire("style.load");
  }

  layerIds() {
    return this.layers.map((layer) => layer.id);
  }

  sourceObject(id, spec) {
    return {
      type: spec.type,
      spec,
      setData: (data) => this.record("setData", id, data),
      updateImage: (options) => this.record("updateImage", id, options),
    };
  }

  // --- style ---------------------------------------------------------------

  setStyle(style, options) {
    this.record("setStyle", style, options);
  }

  addSource(id, spec) {
    this.record("addSource", id, spec);

    if (this.sources.has(id)) {
      throw new Error(`There is already a source with ID "${id}".`);
    }

    this.sources.set(id, this.sourceObject(id, spec));
  }

  getSource(id) {
    return this.sources.get(id);
  }

  removeSource(id) {
    this.record("removeSource", id);
    const user = this.layers.find((layer) => layer.source === id);

    if (user) {
      throw new Error(`Source "${id}" cannot be removed while layer "${user.id}" is using it.`);
    }

    this.sources.delete(id);
  }

  // MapLibre validates a layer against the style before adding it. A layer
  // that fails is reported as an error and left off the map, not thrown.
  addLayer(layer, before) {
    this.record("addLayer", layer, before);

    if (this.getLayer(layer.id)) {
      throw new Error(`Layer "${layer.id}" already exists on this map.`);
    }

    const invalid = this.layerError(layer);

    if (invalid) {
      this.reportError(new Error(`layers.${layer.id}: ${invalid}`));
      return;
    }

    const at = before === undefined ? -1 : this.layers.findIndex((each) => each.id === before);
    const copy = { ...layer, paint: { ...layer.paint }, layout: { ...layer.layout } };

    if (at === -1) {
      this.layers.push(copy);
    } else {
      this.layers.splice(at, 0, copy);
    }
  }

  // Why MapLibre's layer validation would refuse `layer`, or null. Only two of
  // its checks are modelled: a source the style does not hold, and a vector
  // source with no `source-layer` to read from.
  layerError(layer) {
    if (layer.type === "background" || layer.source === undefined) {
      return null;
    }

    const source = this.getSource(layer.source);

    if (!source) {
      return `source "${layer.source}" not found`;
    }

    if (source.type === "vector" && !layer["source-layer"]) {
      return `layer "${layer.id}" must specify a "source-layer"`;
    }

    return null;
  }

  // MapLibre fires an `error` event rather than throwing, and logs the error
  // with console.error when nothing listens for it.
  reportError(error) {
    if (this.listenerCount("error") > 0) {
      this.fire("error", { error });
    } else {
      console.error(error);
    }
  }

  getLayer(id) {
    return this.layers.find((layer) => layer.id === id);
  }

  removeLayer(id) {
    this.record("removeLayer", id);
    this.layers = this.layers.filter((layer) => layer.id !== id);
  }

  moveLayer(id, before) {
    this.record("moveLayer", id, before);
  }

  setPaintProperty(id, name, value) {
    this.record("setPaintProperty", id, name, value);
    this.getLayer(id).paint[name] = value;
  }

  setLayoutProperty(id, name, value) {
    this.record("setLayoutProperty", id, name, value);
    this.getLayer(id).layout[name] = value;
  }

  setFilter(id, filter) {
    this.record("setFilter", id, filter);
    this.getLayer(id).filter = filter;
  }

  setLayerZoomRange(id, minzoom, maxzoom) {
    this.record("setLayerZoomRange", id, minzoom, maxzoom);
  }

  setTerrain(terrain) {
    this.record("setTerrain", terrain);
  }

  setSky(sky) {
    this.record("setSky", sky);
  }

  // --- overlays ------------------------------------------------------------

  addControl(control, position) {
    this.record("addControl", control, position);
    this.controls.push({ control, position });
  }

  removeControl(control) {
    this.record("removeControl", control);
    this.controls = this.controls.filter((each) => each.control !== control);
  }

  // --- camera --------------------------------------------------------------

  // MapLibre emits the move events of a jump synchronously, carrying the
  // event data it was given.
  jumpTo(camera, eventData = {}) {
    this.record("jumpTo", camera, eventData);
    this.camera = { ...this.camera, ...camera };
    this.fire("movestart", { ...eventData });
    this.fire("moveend", { ...eventData });
  }

  setMaxBounds(bounds) {
    this.record("setMaxBounds", bounds);
  }

  setMinZoom(zoom) {
    this.record("setMinZoom", zoom);
  }

  setMaxZoom(zoom) {
    this.record("setMaxZoom", zoom);
  }

  setMinPitch(pitch) {
    this.record("setMinPitch", pitch);
  }

  setMaxPitch(pitch) {
    this.record("setMaxPitch", pitch);
  }

  getCenter() {
    return this.camera.center;
  }

  getZoom() {
    return this.camera.zoom;
  }

  getBearing() {
    return this.camera.bearing;
  }

  getPitch() {
    return this.camera.pitch;
  }

  getBounds() {
    return {
      getWest: () => -10,
      getSouth: () => -5,
      getEast: () => 10,
      getNorth: () => 5,
    };
  }

  remove() {
    this.record("remove");
    this.removed = true;
  }
}

export { FakeMap as Map };

export class Marker extends Evented {
  constructor(options = {}) {
    super();
    this.options = options;
    this.element = options.element || document.createElement("div");
    this.lngLat = null;
    this.map = null;
    this.popup = null;
    this.calls = [];
  }

  setLngLat(lngLat) {
    this.calls.push(["setLngLat", lngLat]);
    this.lngLat = Array.isArray(lngLat) ? { lng: lngLat[0], lat: lngLat[1] } : lngLat;
    return this;
  }

  getLngLat() {
    return this.lngLat;
  }

  getElement() {
    return this.element;
  }

  addTo(map) {
    this.map = map;
    map.markers.add(this);
    return this;
  }

  remove() {
    if (this.map) {
      this.map.markers.delete(this);
    }

    this.map = null;
    return this;
  }

  setPopup(popup) {
    this.popup = popup;
    return this;
  }

  setOffset(offset) {
    this.calls.push(["setOffset", offset]);
    return this;
  }

  setDraggable(draggable) {
    this.calls.push(["setDraggable", draggable]);
    return this;
  }

  setRotation(rotation) {
    this.calls.push(["setRotation", rotation]);
    return this;
  }
}

export class Popup extends Evented {
  constructor(options = {}) {
    super();
    this.options = options;
    this.lngLat = null;
    this.html = null;
    this.map = null;
  }

  setLngLat(lngLat) {
    this.lngLat = lngLat;
    return this;
  }

  setHTML(html) {
    this.html = html;
    return this;
  }

  // MapLibre fires `open` at the very end of addTo, synchronously, so a
  // listener attached once addTo has returned never hears it.
  addTo(map) {
    if (this.map) {
      this.remove();
    }

    this.map = map;
    map.popups.add(this);
    this.fire("open");
    return this;
  }

  isOpen() {
    return this.map !== null;
  }

  // `close` fires only when the popup was on a map.
  remove() {
    if (this.map) {
      this.map.popups.delete(this);
      this.map = null;
      this.fire("close");
    }

    return this;
  }
}

class Control {
  constructor(options = {}) {
    this.options = options;
  }
}

export class NavigationControl extends Control {}
export class ScaleControl extends Control {}
export class GeolocateControl extends Control {}
export class FullscreenControl extends Control {}
export class AttributionControl extends Control {}
export class GlobeControl extends Control {}
export class TerrainControl extends Control {}
