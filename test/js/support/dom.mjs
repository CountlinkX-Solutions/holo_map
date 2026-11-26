// A document just large enough for runtime.mjs.
//
// The runtime touches a small slice of the DOM: elements with attributes and
// children (appended, inserted and walked as siblings), `getElementById`,
// `querySelector(All)` with attribute and class selectors, `innerHTML` as an
// opaque string, `isConnected`, DOM listeners with bubbling, and
// MutationObserver. Implementing that slice here keeps the unit
// tests free of any npm dependency, so `node --test` runs them on a fresh
// checkout.
//
// MutationObserver matters most: it is how the runtime learns that Hologram
// patched a definition. Mutations are recorded synchronously and delivered in
// a microtask, as a browser does, so a test changes an attribute and then
// awaits `settle()` before asserting on the map.

const registrations = new Set();

class Element {
  constructor(document, tagName) {
    this.ownerDocument = document;
    this.tagName = tagName.toUpperCase();
    this.attributes = new Map();
    this.children = [];
    this.parentNode = null;
    this.html = "";
    this.listeners = [];
  }

  get id() {
    return this.getAttribute("id") || "";
  }

  set id(value) {
    this.setAttribute("id", value);
  }

  get className() {
    return this.getAttribute("class") || "";
  }

  set className(value) {
    this.setAttribute("class", value);
  }

  get isConnected() {
    let node = this;

    while (node.parentNode) {
      node = node.parentNode;
    }

    return node === this.ownerDocument.documentElement;
  }

  // Slot markup is only ever read back and handed to MapLibre as a string, so
  // it is kept as one. Writing it is still a child-list mutation.
  get innerHTML() {
    return this.html;
  }

  set innerHTML(value) {
    this.html = String(value);
    notify(this, { type: "childList", attributeName: null });
  }

  getAttribute(name) {
    return this.attributes.has(name) ? this.attributes.get(name) : null;
  }

  hasAttribute(name) {
    return this.attributes.has(name);
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
    notify(this, { type: "attributes", attributeName: name });
  }

  removeAttribute(name) {
    this.attributes.delete(name);
    notify(this, { type: "attributes", attributeName: name });
  }

  get firstElementChild() {
    return this.children[0] || null;
  }

  get lastElementChild() {
    return this.children[this.children.length - 1] || null;
  }

  get nextSibling() {
    if (!this.parentNode) {
      return null;
    }

    const siblings = this.parentNode.children;
    return siblings[siblings.indexOf(this) + 1] || null;
  }

  appendChild(child) {
    if (child.parentNode) {
      child.parentNode.removeChild(child);
    }

    child.parentNode = this;
    this.children.push(child);
    notify(this, { type: "childList", attributeName: null });

    return child;
  }

  // Puts `child` before `reference`, or last when `reference` is null, and
  // throws as the DOM does when `reference` is not a child of this element.
  insertBefore(child, reference) {
    if (reference === null || reference === undefined) {
      return this.appendChild(child);
    }

    if (child.parentNode) {
      child.parentNode.removeChild(child);
    }

    const at = this.children.indexOf(reference);

    if (at === -1) {
      throw new Error("insertBefore: the reference node is not a child of this node");
    }

    child.parentNode = this;
    this.children.splice(at, 0, child);
    notify(this, { type: "childList", attributeName: null });

    return child;
  }

  removeChild(child) {
    this.children = this.children.filter((node) => node !== child);
    child.parentNode = null;
    notify(this, { type: "childList", attributeName: null });

    return child;
  }

  remove() {
    if (this.parentNode) {
      this.parentNode.removeChild(this);
    }
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] || null;
  }

  querySelectorAll(selector) {
    const matchers = selector.split(",").map((part) => compile(part.trim()));
    const found = [];

    walk(this, (node) => {
      if (matchers.some((matches) => matches(node))) {
        found.push(node);
      }
    });

    return found;
  }

  addEventListener(name, listener) {
    this.listeners.push({ name, listener });
  }

  removeEventListener(name, listener) {
    this.listeners = this.listeners.filter(
      (record) => record.name !== name || record.listener !== listener,
    );
  }

  // Like Node.contains, true for the node itself too.
  contains(node) {
    for (let current = node; current; current = current.parentNode) {
      if (current === this) {
        return true;
      }
    }

    return false;
  }

  // Delivers a minimal event to this element's listeners, then bubbles it up
  // through its ancestors until a listener stops it. Only the bubble phase is
  // modelled: neither the runtime nor MapLibre's click handling captures.
  //
  // This is an event a script dispatches. Every listener runs before control
  // comes back, so a microtask that a listener queues waits for all of them.
  dispatchEvent(event) {
    for (const _listener of propagate(this, event)) {
      // Nothing runs between two listeners.
    }
  }

  // The same event coming from the user's input instead, such as a real click.
  // The browser dispatches it as a task of its own with no script on the
  // stack, so each time a listener returns it runs every microtask queued so
  // far. A timer is a task of its own and still waits for the whole dispatch.
  // Resolves once the dispatch is over.
  async dispatchUserEvent(event) {
    for (const _listener of propagate(this, event)) {
      await microtaskCheckpoint();
    }
  }
}

// Calls the listeners an event reaches, in order, yielding after each one. The
// path is fixed before the first listener runs, as the DOM fixes it, so a
// listener that moves or removes a node does not change where the event goes.
function* propagate(target, event) {
  let stopped = false;

  const delivered = {
    ...event,
    target,
    stopPropagation() {
      stopped = true;
    },
  };

  const path = [];

  for (let node = target; node; node = node.parentNode) {
    path.push(node);
  }

  for (const node of path) {
    if (stopped) {
      return;
    }

    delivered.currentTarget = node;

    for (const record of node.listeners.filter(({ name }) => name === delivered.type)) {
      record.listener(delivered);
      yield record;
    }
  }
}

// Resolves once the microtask queue is empty, microtasks queued by microtasks
// included, before any timer or immediate can run. Node runs a `nextTick`
// callback queued from inside a microtask only after draining the whole queue,
// and runs both before it returns to its event loop.
async function microtaskCheckpoint() {
  // Continues inside a microtask, so the tick below is queued from one.
  await null;
  await new Promise((resolve) => process.nextTick(resolve));
}

class Document {
  constructor() {
    this.documentElement = new Element(this, "html");
    this.body = new Element(this, "body");
    this.documentElement.appendChild(this.body);
  }

  createElement(tagName) {
    return new Element(this, tagName);
  }

  getElementById(id) {
    let found = null;

    walk(this.documentElement, (node) => {
      if (!found && node.id === id) {
        found = node;
      }
    });

    return found;
  }
}

class MutationObserver {
  constructor(callback) {
    this.callback = callback;
    this.targets = [];
    this.records = [];
    this.scheduled = false;
  }

  observe(target, options) {
    this.targets.push({ target, options });
    registrations.add(this);
  }

  disconnect() {
    this.targets = [];
    this.records = [];
    registrations.delete(this);
  }

  takeRecords() {
    const records = this.records;
    this.records = [];
    return records;
  }
}

function notify(node, record) {
  registrations.forEach((observer) => {
    if (!observer.targets.some((registration) => observes(registration, node, record))) {
      return;
    }

    observer.records.push({ ...record, target: node });

    if (!observer.scheduled) {
      observer.scheduled = true;

      queueMicrotask(() => {
        observer.scheduled = false;
        const records = observer.takeRecords();

        if (records.length > 0 && registrations.has(observer)) {
          observer.callback(records, observer);
        }
      });
    }
  });
}

function observes({ target, options }, node, record) {
  const inScope = node === target || (options.subtree && contains(target, node));

  if (!inScope) {
    return false;
  }

  if (record.type === "childList") {
    return Boolean(options.childList);
  }

  return (
    Boolean(options.attributes) &&
    (!options.attributeFilter || options.attributeFilter.includes(record.attributeName))
  );
}

function contains(ancestor, node) {
  for (let current = node.parentNode; current; current = current.parentNode) {
    if (current === ancestor) {
      return true;
    }
  }

  return false;
}

function walk(root, visit) {
  root.children.forEach((child) => {
    visit(child);
    walk(child, visit);
  });
}

// Supports the selector forms the runtime uses: `[name]`, `[name="value"]`
// and `.class`.
function compile(selector) {
  const attribute = selector.match(/^\[([\w-]+)(?:="([^"]*)")?\]$/);

  if (attribute) {
    const [, name, value] = attribute;

    return (node) =>
      node.hasAttribute(name) && (value === undefined || node.getAttribute(name) === value);
  }

  const className = selector.match(/^\.([\w-]+)$/);

  if (className) {
    return (node) => node.className.split(/\s+/).includes(className[1]);
  }

  throw new Error(`the test DOM does not support the selector ${JSON.stringify(selector)}`);
}

// Installs the document and the browser globals the runtime reads.
export function installDOM() {
  const document = new Document();

  globalThis.document = document;
  globalThis.window = globalThis;
  globalThis.MutationObserver = MutationObserver;
  globalThis.requestAnimationFrame = (callback) => setTimeout(callback, 0);

  return document;
}

// Resolves once every pending mutation has been delivered and the work it
// triggered has run.
export function settle() {
  return new Promise((resolve) => setImmediate(resolve));
}

// Resolves in a task after every timer already set with no delay, which is
// where the runtime reports a click on a marker.
export function nextTask() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}
