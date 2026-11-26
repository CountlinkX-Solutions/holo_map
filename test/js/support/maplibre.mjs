// Stands in for maplibre-gl in the runtime unit tests.
//
// Every class records the calls the runtime makes and keeps just the state
// those calls imply (the sources, the layer stack, images, controls in their
// corners, markers and popups on the map, a marker's popup and alignment, a popup's options and
// classes), so a test can assert both on what was asked and on what a real
// map would now hold. Nothing here renders, fetches or parses.
//
// MapLibre's events are driven by hand: `map.loadStyle()` plays a style
// arriving, which replaces the style-scoped state and emits `style.load`, and
// `fire()` emits any other event. Clicks can also go through the DOM: one
// dispatched on a marker's element bubbles to the map's canvas container,
// which turns it into the map's `click` as MapLibre does.
//
// As in MapLibre, the style methods throw "Style is not done loading." until
// a style has loaded, and again while setStyle rebuilds the style.

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
    // Registered images by name. MapLibre keeps them on the style object, so
    // a style that setStyle rebuilds starts without them.
    this.images = new Map();
    this.terrain = null;
    // The style given to the constructor is still on its way.
    this.styleLoaded = false;
    this.styleRequest = { diff: false };
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

    // One element per corner for the controls, with MapLibre's class names.
    this.controlContainer = document.createElement("div");
    this.controlContainer.className = "maplibregl-control-container";
    this.corners = {};

    ["top-left", "top-right", "bottom-left", "bottom-right"].forEach((position) => {
      const corner = document.createElement("div");
      corner.className = `maplibregl-ctrl-${position} `;
      this.controlContainer.appendChild(corner);
      this.corners[position] = corner;
    });

    options.container.appendChild(this.controlContainer);

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

  // Plays a style arriving: the map's first style, or the response to the
  // setStyle call before it. A style that setStyle diffs is applied as diff()
  // describes. Any other replaces whatever the previous style held with its
  // own sources and layers, and no terrain, and `style.load` fires.
  loadStyle(style = {}) {
    const request = this.styleRequest;
    this.styleRequest = null;

    if (request && request.diff) {
      this.diff(style);
      return;
    }

    const { sources = {}, layers = [] } = style;

    this.sources = new Map(
      Object.entries(sources).map(([id, spec]) => [id, this.sourceObject(id, spec)]),
    );
    this.layers = layers.map((layer) => ({ ...layer }));
    this.terrain = null;
    this.styleLoaded = true;
    this.fire("style.load");
  }

  // MapLibre's diff: the current style, with the sources and layers added to
  // it since it loaded, is compared with `style`. What `style` lacks goes,
  // what it adds comes, a source it leaves unchanged stays the same object,
  // and `style.load` fires, but only if anything changed. A change MapLibre
  // cannot diff (a new sprite or glyphs) makes it rebuild instead; no test
  // depends on that, so it is not modelled.
  diff({ sources = {}, layers = [] } = {}) {
    const current = Object.fromEntries(
      Array.from(this.sources, ([id, source]) => [id, source.spec]),
    );

    if (
      JSON.stringify(current) === JSON.stringify(sources) &&
      JSON.stringify(this.layers) === JSON.stringify(layers)
    ) {
      return;
    }

    this.sources = new Map(
      Object.entries(sources).map(([id, spec]) => {
        const kept = this.sources.get(id);
        const same = kept && JSON.stringify(kept.spec) === JSON.stringify(spec);
        return [id, same ? kept : this.sourceObject(id, spec)];
      }),
    );
    this.layers = layers.map((layer) => ({ ...layer }));
    this.fire("style.load");
  }

  // What MapLibre's style methods check first.
  checkLoaded() {
    if (!this.styleLoaded) {
      throw new Error("Style is not done loading.");
    }
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

  // MapLibre diffs the new style against the current one, unless the options
  // say `diff: false` or no style has loaded yet. Otherwise it builds a new
  // style object, which holds no source, layer or image and takes no work
  // until it has loaded; the terrain stays until then. A style given by URL
  // is fetched first either way, and loadStyle() plays the response
  // arriving. An object to diff is diffed at once.
  setStyle(style, options) {
    this.record("setStyle", style, options);

    if ((!options || options.diff !== false) && this.styleLoaded) {
      if (typeof style === "string") {
        this.styleRequest = { diff: true };
      } else {
        this.diff(style);
      }

      return;
    }

    this.styleLoaded = false;
    this.styleRequest = { diff: false };
    this.sources = new Map();
    this.layers = [];
    this.images = new Map();
  }

  addSource(id, spec) {
    this.record("addSource", id, spec);
    this.checkLoaded();

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
    this.checkLoaded();
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
    this.checkLoaded();

    if (this.getLayer(layer.id)) {
      throw new Error(`Layer "${layer.id}" already exists on this map.`);
    }

    const invalid = this.layerError(layer);

    if (invalid) {
      this.reportError(new Error(`layers.${layer.id}: ${invalid}`));
      return;
    }

    // Without `before` the layer goes on top. A `before` naming no layer is
    // an error, and the layer is left off the map.
    const at = before ? this.layers.findIndex((each) => each.id === before) : this.layers.length;

    if (at === -1) {
      this.reportError(
        new Error(`Cannot add layer "${layer.id}" before non-existing layer "${before}".`),
      );
      return;
    }

    this.layers.splice(at, 0, { ...layer, paint: { ...layer.paint }, layout: { ...layer.layout } });
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
    this.checkLoaded();
    this.layers = this.layers.filter((layer) => layer.id !== id);
  }

  // The layer ids, bottom to top.
  getLayersOrder() {
    return this.layerIds();
  }

  // MapLibre takes the layer out of its stack before looking for `before`, so
  // a `before` naming no layer reports an error and leaves the layer out of
  // the stack, which here means off the map.
  moveLayer(id, before) {
    this.record("moveLayer", id, before);
    this.checkLoaded();
    const layer = this.getLayer(id);

    if (!layer) {
      this.reportError(
        new Error(`The layer '${id}' does not exist in the map's style and cannot be moved.`),
      );
      return;
    }

    if (id === before) {
      return;
    }

    this.layers = this.layers.filter((each) => each !== layer);
    const at = before ? this.layers.findIndex((each) => each.id === before) : this.layers.length;

    if (at === -1) {
      this.reportError(
        new Error(`Cannot move layer "${id}" before non-existing layer "${before}".`),
      );
      return;
    }

    this.layers.splice(at, 0, layer);
  }

  setPaintProperty(id, name, value) {
    this.record("setPaintProperty", id, name, value);
    this.checkLoaded();
    this.getLayer(id).paint[name] = value;
  }

  setLayoutProperty(id, name, value) {
    this.record("setLayoutProperty", id, name, value);
    this.checkLoaded();
    this.getLayer(id).layout[name] = value;
  }

  setFilter(id, filter) {
    this.record("setFilter", id, filter);
    this.checkLoaded();
    this.getLayer(id).filter = filter;
  }

  setLayerZoomRange(id, minzoom, maxzoom) {
    this.record("setLayerZoomRange", id, minzoom, maxzoom);
    this.checkLoaded();
  }

  setTerrain(terrain) {
    this.record("setTerrain", terrain);
    this.checkLoaded();
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
    this.checkLoaded();
  }

  // --- overlays ------------------------------------------------------------

  // MapLibre appends the control's element to a top corner and puts it first
  // in a bottom one, so each control added lands farthest from the map's edge.
  addControl(control, position) {
    this.record("addControl", control, position);
    const element = control.onAdd(this);
    this.controls.push({ control, position });

    const corner = this.corners[position];

    if (position.includes("bottom")) {
      corner.insertBefore(element, corner.firstElementChild);
    } else {
      corner.appendChild(element);
    }
  }

  removeControl(control) {
    this.record("removeControl", control);
    this.controls = this.controls.filter((each) => each.control !== control);
    control.onRemove(this);
  }

  // The controls in a corner as the page shows them, top to bottom.
  controlsIn(position) {
    return this.corners[position].children.map(
      (element) => this.controls.find(({ control }) => control.element === element).control,
    );
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

// MapLibre's controls build an element when added to a map and take it out of
// the page when removed.
class Control {
  constructor(options = {}) {
    this.options = options;
    this.element = null;
  }

  onAdd() {
    this.element = document.createElement("div");
    this.element.className = "maplibregl-ctrl";
    return this.element;
  }

  onRemove() {
    this.element.remove();
  }
}

export class NavigationControl extends Control {}
export class ScaleControl extends Control {}
export class GeolocateControl extends Control {}
export class FullscreenControl extends Control {}
export class AttributionControl extends Control {}
export class GlobeControl extends Control {}
export class TerrainControl extends Control {}
