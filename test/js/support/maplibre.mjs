// Stands in for maplibre-gl in the runtime unit tests.
//
// Every class records the calls the runtime makes and keeps just the state
// those calls imply (the sources, the layer stack, images, controls, markers
// and popups on the map, a marker's popup and alignment, a popup's options and
// classes), so a test can assert both on what was asked and on what a real
// map would now hold. Nothing here renders, fetches or parses.
//
// MapLibre's events are driven by hand: `map.loadStyle()` plays a style
// arriving, which wipes the style-scoped state and emits `style.load`, and
// `fire()` emits any other event. Clicks can also go through the DOM: one
// dispatched on a marker's element bubbles to the map's canvas container,
// which turns it into the map's `click` as MapLibre does.

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
    // Registered images by name. A style arriving leaves them alone: no test
    // swaps styles with images registered.
    this.images = new Map();
    this.controls = [];
    this.markers = new Set();
    this.popups = new Set();
    this.camera = { center: { lng: 0, lat: 0 }, zoom: 0, bearing: 0, pitch: 0 };
    this.removed = false;

    // Features a test places under the pointer, by layer id, for the layer
    // events a click delegates.
    this.featuresUnderPointer = {};

    // MapLibre builds this inside the container and puts marker elements in
    // it. Its own `click` comes from DOM clicks that bubble up to it, through
    // a listener in the bubble phase.
    this.canvasContainer = document.createElement("div");
    this.canvasContainer.className = "maplibregl-canvas-container";
    this.canvasContainer.addEventListener("click", (event) => this.click(event));
    options.container.appendChild(this.canvasContainer);

    maps.push(this);
  }

  getCanvasContainer() {
    return this.canvasContainer;
  }

  // The map `click` MapLibre fires for a DOM click that reached the canvas
  // container, then the layer `click`s it delegates from that same event for
  // the features under the pointer. Nothing is projected: every click lands
  // on the camera's centre.
  click(originalEvent) {
    const event = {
      type: "click",
      originalEvent,
      point: { x: originalEvent.clientX ?? 0, y: originalEvent.clientY ?? 0 },
      lngLat: this.camera.center,
    };

    this.fire("click", event);

    Object.entries(this.featuresUnderPointer).forEach(([layer, features]) => {
      this.fire("click", { ...event, features }, layer);
    });
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

  // --- images --------------------------------------------------------------

  // Resolves the way MapLibre's image request does, with the image under
  // `data`. Nothing is fetched: the image stands in as its URL.
  loadImage(url) {
    this.record("loadImage", url);
    return Promise.resolve({ data: { url } });
  }

  hasImage(id) {
    return this.images.has(id);
  }

  // Both report a name that is taken, or missing, as an error event.
  addImage(id, image, options = {}) {
    this.record("addImage", id, image, options);

    if (this.images.has(id)) {
      this.reportError(new Error(`An image named "${id}" already exists.`));
      return;
    }

    this.images.set(id, { image, options });
  }

  removeImage(id) {
    this.record("removeImage", id);

    if (!this.images.has(id)) {
      this.reportError(new Error(`An image named "${id}" does not exist.`));
      return;
    }

    this.images.delete(id);
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

// MapLibre resolves an unset or "auto" pitch alignment to the rotation
// alignment, both when it builds a marker and in setPitchAlignment.
function pitchAlignmentFor(alignment, rotationAlignment) {
  return alignment && alignment !== "auto" ? alignment : rotationAlignment;
}

// A class name as DOMTokenList takes it: MapLibre hands names straight to
// classList, which throws on an empty one or one holding whitespace.
function classToken(name) {
  if (name === "" || /\s/.test(name)) {
    throw new Error(`classList refuses the class name ${JSON.stringify(name)}`);
  }

  return name;
}

export class Marker extends Evented {
  constructor(options = {}) {
    super();
    this.options = options;
    this.element = options.element || document.createElement("div");
    this.lngLat = null;
    this.map = null;
    this.popup = null;
    this.calls = [];

    // What the setters below change, starting where MapLibre's constructor
    // leaves it.
    this.opacity = options.opacity === undefined ? "1" : String(options.opacity);
    this.rotationAlignment = options.rotationAlignment || "auto";
    this.pitchAlignment = pitchAlignmentFor(options.pitchAlignment, this.rotationAlignment);
    this.subpixelPositioning = options.subpixelPositioning || false;
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

  // MapLibre puts the element in the canvas container, and toggles the
  // marker's popup from the map's own `click`, not from the element's.
  addTo(map) {
    this.map = map;
    map.markers.add(this);
    map.getCanvasContainer().appendChild(this.element);
    map.on("click", this.onMapClick);
    return this;
  }

  // Takes the marker's element and popup off the map with it.
  remove() {
    if (this.map) {
      this.map.off("click", this.onMapClick);
      this.map.markers.delete(this);
    }

    this.map = null;
    this.element.remove();

    if (this.popup) {
      this.popup.remove();
    }

    return this;
  }

  // MapLibre's _onMapClick: a map click that started on this marker's element
  // toggles its popup.
  onMapClick = (event) => {
    if (this.popup && this.element.contains(event.originalEvent.target)) {
      this.togglePopup();
    }
  };

  // Replacing or clearing the popup closes the one attached before.
  setPopup(popup) {
    if (this.popup) {
      this.popup.remove();
      this.popup = null;
    }

    if (popup) {
      this.popup = popup;
    }

    return this;
  }

  getPopup() {
    return this.popup;
  }

  togglePopup() {
    if (!this.popup) {
      return this;
    }

    if (this.popup.isOpen()) {
      this.popup.remove();
    } else {
      this.popup.setLngLat(this.lngLat);
      this.popup.addTo(this.map);
    }

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

  // Called with no opacity, MapLibre resets it to its default.
  setOpacity(opacity) {
    this.calls.push(["setOpacity", opacity]);
    this.opacity = opacity === undefined ? "1" : String(opacity);
    return this;
  }

  setRotationAlignment(alignment) {
    this.calls.push(["setRotationAlignment", alignment]);
    this.rotationAlignment = alignment || "auto";
    return this;
  }

  setPitchAlignment(alignment) {
    this.calls.push(["setPitchAlignment", alignment]);
    this.pitchAlignment = pitchAlignmentFor(alignment, this.rotationAlignment);
    return this;
  }

  setSubpixelPositioning(value) {
    this.calls.push(["setSubpixelPositioning", value]);
    this.subpixelPositioning = value;
    return this;
  }
}

export class Popup extends Evented {
  constructor(options = {}) {
    super();
    // MapLibre copies the options it is given, and its setters write to the
    // copy.
    this.options = { ...options };
    this.lngLat = null;
    this.html = null;
    this.map = null;
    // The classes on the popup's container, which exists only while the
    // popup is open.
    this.classes = null;
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

    // Of the ways MapLibre closes a popup on its own, only `closeOnClick` (on
    // unless the options turn it off) is modelled.
    if (!("closeOnClick" in this.options) || this.options.closeOnClick) {
      map.on("click", this.onClose);
    }

    // MapLibre splits `className` on single spaces when it builds the
    // container, so two spaces in a row reach classList as an empty name.
    const names = this.options.className ? this.options.className.split(" ") : [];
    this.classes = new Set(names.map(classToken));
    this.fire("open");
    return this;
  }

  isOpen() {
    return this.map !== null;
  }

  // `close` fires only when the popup was on a map.
  remove() {
    if (this.map) {
      this.map.off("click", this.onClose);
      this.map.popups.delete(this);
      this.map = null;
      this.classes = null;
      this.fire("close");
    }

    return this;
  }

  onClose = () => {
    this.remove();
  };

  setMaxWidth(maxWidth) {
    this.options.maxWidth = maxWidth;
    return this;
  }

  setOffset(offset) {
    this.options.offset = offset;
    return this;
  }

  // Returns nothing in MapLibre, unlike the other setters.
  setSubpixelPositioning(value) {
    this.options.subpixelPositioning = value;
  }

  // Both work on the container, so they do nothing while the popup is closed.
  addClassName(name) {
    if (this.classes) {
      this.classes.add(classToken(name));
    }

    return this;
  }

  removeClassName(name) {
    if (this.classes) {
      this.classes.delete(classToken(name));
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
