// Loads runtime.mjs against the fake maplibre-gl and the test DOM, and builds
// the markup HoloMap's components render: a container `hm--<cid>` and, next to
// it, a hidden `hm--<cid>--defs` element holding one definition element per
// component (`data-hm`, `data-hm-key`, `data-hm-map`, `data-hm-spec`,
// `data-hm-events`).
//
// runtime.mjs imports the bare specifier "maplibre-gl", which nothing in this
// repository installs. A module resolution hook answers it with the fake
// instead, before the runtime is imported, which is why the runtime is loaded
// with a dynamic import rather than a static one.

import * as nodeModule from "node:module";
import { installDOM, nextTask, settle } from "./dom.mjs";

if (typeof nodeModule.registerHooks !== "function") {
  throw new Error(
    "the runtime unit tests need Node.js 22.15 or later (module.registerHooks), " +
      `not ${process.version}`,
  );
}

const fakeMapLibre = new URL("./maplibre.mjs", import.meta.url).href;

nodeModule.registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "maplibre-gl") {
      return { url: fakeMapLibre, shortCircuit: true };
    }

    return nextResolve(specifier, context);
  },
});

const document = installDOM();

export const runtime = await import("../../../lib/holo_map/js/runtime.mjs");
export const maplibre = await import("maplibre-gl");
export { nextTask, settle };

// Actions the runtime dispatched, as [action, target, params], newest last.
export const dispatched = [];

window.Hologram = {
  dispatchAction(action, target, params) {
    dispatched.push([action, target, params]);
  },
};

// What the runtime logged. It reports a definition that failed through
// console.error rather than by throwing, so the tests read it from here.
export const logged = { errors: [], warnings: [] };

const describeArgs = (args) =>
  args.map((arg) => (arg instanceof Error ? arg.stack : String(arg))).join(" ");

console.error = (...args) => logged.errors.push(describeArgs(args));
console.warn = (...args) => logged.warnings.push(describeArgs(args));

let mounted = 0;
const live = [];

const DEFAULT_SPEC = { style: "https://tiles.test/style.json" };

// Renders a map's container and definitions, boots it unless `boot` is false,
// and returns a handle for driving it. `defs` lists child definitions in
// template order.
export function mountMap({ spec = DEFAULT_SPEC, events, defs = [], boot = true } = {}) {
  mounted += 1;
  const cid = `map${mounted}`;

  const container = document.createElement("div");
  container.id = `hm--${cid}`;

  const holder = document.createElement("div");
  holder.id = `hm--${cid}--defs`;
  holder.appendChild(definition(cid, { kind: "map", key: "map", spec, events }));
  defs.forEach((def) => holder.appendChild(definition(cid, def)));

  const wrapper = document.createElement("div");
  wrapper.appendChild(container);
  wrapper.appendChild(holder);
  document.body.appendChild(wrapper);

  if (boot) {
    runtime.boot(cid);
  }

  // The definition element for `key`. Definitions of different kinds can
  // share a key, as a source and its layer often do, so `kind` picks one.
  const def = (key, kind) =>
    holder.children.find(
      (element) =>
        element.getAttribute("data-hm-key") === key &&
        (kind === undefined || element.getAttribute("data-hm") === kind),
    );

  const handle = {
    cid,
    container,
    wrapper,
    // The MapLibre map built on this container, once the map has booted.
    get map() {
      return maplibre.maps.findLast((map) => map.options.container === container);
    },
    boot: () => runtime.boot(cid),
    def,
    // Appends a definition, or renders it just before the one keyed `before`.
    add: (spec, before) =>
      holder.insertBefore(definition(cid, spec), before === undefined ? null : def(before)),
    remove: (key, kind) => holder.removeChild(def(key, kind)),
    setSpec: (key, value, kind) =>
      def(key, kind).setAttribute("data-hm-spec", JSON.stringify(value)),
    unmount() {
      runtime.destroy(cid);
      wrapper.remove();
    },
  };

  live.push(handle);
  return handle;
}

// Tears down every map a test mounted, so the next test starts from an empty
// document and an empty registry.
export function unmountAll() {
  live.splice(0).forEach((handle) => handle.unmount());
}

// One definition element, with an optional slot (`content`) the way Marker
// and Popup render theirs.
export function definition(cid, { kind, key, spec = {}, events, content }) {
  const element = document.createElement("div");
  element.setAttribute("data-hm", kind);
  element.setAttribute("data-hm-key", key);
  element.setAttribute("data-hm-map", cid);
  element.setAttribute("data-hm-spec", JSON.stringify(spec));

  if (events) {
    element.setAttribute("data-hm-events", JSON.stringify(events));
  }

  if (content !== undefined) {
    const slot = document.createElement("div");
    slot.setAttribute("data-hm-content", "");
    slot.innerHTML = content;
    element.appendChild(slot);
  }

  return element;
}
