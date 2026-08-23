# Limitations

Things that do not work, and why. Most trace back to Hologram being a young
framework with hooks a map library would like and does not have.

## Slot content is cloned

`HoloMap.Marker` and `HoloMap.Popup` accept slot content, and MapLibre receives a
**clone** of it rather than the node Hologram rendered.

MapLibre moves a marker's element into its own overlay container. Handing it the
real node would take that node out from under the virtual DOM and corrupt the
next patch, so the markup is cloned instead.

The consequence: **Hologram event bindings inside the slot do not fire.**

```elixir
<HoloMap.Marker id="office" lng_lat={{-70.66, 19.45}}>
  <button $click={:clicked}>Details</button>   <!-- will not fire -->
</HoloMap.Marker>
```

Use the marker's own `on_click` prop instead:

```elixir
<HoloMap.Marker id="office" lng_lat={{-70.66, 19.45}} on_click={:clicked}>
  <div class="chip">Head office</div>
</HoloMap.Marker>
```

The markup still renders and restyles normally on re-render. Only the bindings
are inert. For genuinely interactive content, put it outside the map and drive
it from state.

## Raw HTML must arrive through an expression

Hologram HTML-escapes literal text attributes before a component ever sees them.
So this renders visible `<b>` characters:

```elixir
<HoloMap.Popup id="p" lng_lat={@coords} html="<b>hi</b>" />   <!-- escaped -->
```

and this does not:

```elixir
<HoloMap.Popup id="p" lng_lat={@coords} html={@html} />       <!-- fine -->
```

Slot content has no such caveat. This applies to `HoloMap.Popup`'s `html` and
`HoloMap.Marker`'s `popup_html`.

## Bare boolean attributes

In a HOLO template a bare attribute is an empty *string*, not `true`. `HoloMap`
coerces this for every boolean prop it knows about, so `<... cluster />` works.
A boolean prop it has missed would reach MapLibre as `""` and fail style
validation with `boolean expected, string found`. Pass `={true}` explicitly if
you hit one, and it is worth reporting.

## Controls are replaced, not updated

Changing any prop on a control removes and re-adds it. That is invisible for the
built-ins, but it means a control is not the place to put a rapidly changing
value.

The definition key includes the control's `position`, because MapLibre cannot
move a control between corners in place.

## Structural source changes tear down layers

Only a GeoJSON source's `data` and an image source's `url`/`coordinates` update
in place. Any other source key (cluster settings, tile URLs, zoom ranges) is
structural: MapLibre refuses to remove a source that still has layers attached,
so the reconciler detaches the layers it owns, rebuilds the source, and re-adds
them in declared order.

It works, and it is not free. Put frequently-changing data in `data`.

## MapLibre is bundled once per page

Hologram builds one JavaScript bundle per page, and a page that uses `HoloMap`
carries its own copy of MapLibre, around 1 MB minified and 0.26 MB gzipped. Five
map pages are five distinct downloads.

This is Hologram's bundling model, not something the library can change. It is
also not as bad as it sounds: a visitor only downloads the pages they actually
visit, and each is content-hash named and so cacheable forever. But it does make
compression and cache headers matter more than usual. See
[Installation](installation.html#serving-the-bundles).

## No `HoloMap` styling of its own

The library ships no CSS. MapLibre's own stylesheet is a required install step,
and everything else (sizing, borders, marker chrome) is yours. That is
deliberate: a component library that imposed a look would be fought rather than
used.

## One map per cid

The registry is keyed by `cid`, which is also the DOM container's id. Two
`HoloMap.Map` components with the same `cid` on one page is undefined behaviour
though Hologram itself already requires cids to be unique.

## Hologram gaps this library works around

These are upstream, not `HoloMap`'s, and are worth knowing if you write your own
interop.

**`Map.fetch/2` is broken client-side in Hologram 0.11.0.** The port of
`:maps.find/2` returns the bare value instead of `{:ok, value}`, so the usual
fetch-and-match reduces to a `CaseClauseError` in the browser while working
perfectly on the server. `HoloMap` uses `Map.get/3` with a sentinel instead.
Reported against `bartblast/hologram`.

**`Float.round/2` rejects integers.** MapLibre reports a whole-number coordinate
as an integer, and `Float.round/2` only accepts floats. Widen with `* 1.0`
first. This is standard Elixir behaviour, but it bites more often here because
the values come from JavaScript, where there is no distinction.

**Not all of the standard library is ported.** Hologram's
[client runtime reference](https://hologram.page/reference/client-runtime)
tracks what is available. Anything in a template expression or an action runs in
the browser and is subject to it.

## Things Hologram does not offer yet

- **No "props changed" hook.** This is the whole reason for the DOM definition
  protocol described in [Architecture](architecture.html).
- **No unmount hook.** Disposal is inferred from the container going stale.
  Hologram's roadmap mentions a `setup` (pre-init) hook; an unmount counterpart
  would let `HoloMap` drop a good deal of machinery.
- **Interop only runs in actions.** A map cannot be constructed during SSR, so
  the first paint is always a blank container.

## Not implemented yet

- Nested `HoloMap.Popup` inside a `HoloMap.Marker` slot; use the marker's
  `popup_html` prop
- Server-side rendering of a static map image
