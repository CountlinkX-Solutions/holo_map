# Imperative API

Most of a map belongs in props. Some of it does not.

## When to reach for it

"Fly to the result the user just picked" is an **event**, not a value.
Re-rendering the same centre twice should not re-animate, and animating is the
whole point. That is the category `HoloMap.API` exists for.

| Situation | Use |
| --------- | --- |
| The camera reflects application state | `HoloMap.Map`'s `center` / `zoom` props |
| The camera should animate in response to an event | `fly_to/2`, `ease_to/2` |
| A layer's paint reflects state | `HoloMap.Layer.*`'s `paint` prop |
| A one-off highlight that should not survive a re-render | `set_paint_property/4` |
| Hover and selection styling | `set_feature_state/3` |

Anything set imperatively is overwritten the next time the declarative
specification for that object changes. The reconciler treats rendered props as
the source of truth.

## Calling it

Always from an action, always with the map's `cid` first:

```elixir
def action(:show_parcel, params, component) do
  HoloMap.API.fly_to("explorer", center: {params.lng, params.lat}, zoom: 17)
  put_state(component, :selected, params.id)
end
```

> #### Actions only
>
> These calls compile to no-ops on the server. They work in `action/3` and in
> functions an action reaches; they do nothing in `init/3` or `command/3`.
>
> To move the camera at mount time, chain an action from `init`:
>
> ```elixir
> def init(_params, component, _server) do
>   component
>   |> put_state(:style, @style_url)
>   |> put_action(:frame_data)
> end
> ```

Calls made before the map has booted, or before its style finishes loading, are
queued and replayed in order, so an action scheduled from `init` is not lost,
even when it runs before the map's own boot action. Calls for a map that has not
booted within five seconds are dropped with a console warning.

## Camera

```elixir
HoloMap.API.fly_to("explorer", center: {-70.66, 19.45}, zoom: 14, duration: 1_200)
HoloMap.API.ease_to("explorer", bearing: 45, pitch: 60)
HoloMap.API.jump_to("explorer", center: {-70.66, 19.45})
HoloMap.API.fit_bounds("explorer", [-71.0, 19.0, -70.0, 20.0], padding: 48)
HoloMap.API.resize("explorer")
```

`fly_to/2` arcs out and back in, which reads well over long distances.
`ease_to/2` travels in a straight line, which reads better over short ones.
`jump_to/2` does not animate, which is what a `center` prop change does.

`fit_bounds/3` accepts any shape `HoloMap.Spec.bounds/1` understands: a pair of
corners, or a flat `[west, south, east, north]` list.

`resize/1` is almost never needed. MapLibre observes its own container, so a map
whose container changes size follows along by itself and this call does nothing.
The one case where it is required is a map built with `track_resize={false}`,
which switches that observer off; the demo's camera page has one set up that way
so the difference is visible.

## Layers

```elixir
HoloMap.API.set_filter("explorer", "parcels-fill", ["==", ["get", "zone"], "R1"])
HoloMap.API.set_paint_property("explorer", "parcels-fill", :fill_color, "#ef4444")
HoloMap.API.set_layout_property("explorer", "parcels-fill", :visibility, "none")
```

Property names may be atoms in Elixir style or MapLibre specification names;
both reach MapLibre as the latter.

These duplicate what the `paint`, `layout` and `filter` props already do, and in
almost every case the props are the better choice, because they survive a re-render.
Reach here for something genuinely transient.

## Feature state

Feature state is the mechanism behind hover and selection styling, and it has no
declarative equivalent: it belongs to a *feature*, not to a component.

```elixir
HoloMap.API.set_feature_state("explorer", %{source: "parcels", id: 12}, %{hover: true})
HoloMap.API.remove_feature_state("explorer", %{source: "parcels", id: 12}, "hover")
HoloMap.API.remove_feature_state("explorer", %{source: "parcels", id: 12})
```

Add `:source_layer` for a vector source. Every feature needs an id, which GeoJSON
features often lack. Set `generate_id` on the source, or point `promote_id` at
a property that is already unique. There is a worked example in
[Events](events.html).

## Anything else

`HoloMap.Runtime.call/3` reaches any method on the underlying `maplibregl.Map`:

```elixir
HoloMap.Runtime.call("explorer", "setRenderWorldCopies", [false])
```

It queues against style readiness like everything else, but it does not
normalise its arguments. They are passed to MapLibre as given.

## From JavaScript

A MapLibre plugin (a draw control, a geocoder, a deck.gl overlay) needs the
raw map object, and Hologram's interop cannot hand one to a third-party script.
Every booted map is published on `window`:

```javascript
window.HoloMap.map("explorer")      // the maplibregl.Map, or null
window.HoloMap.cids()               // every live map's cid
window.HoloMap.destroy("explorer")  // release its WebGL context
```

Prefer `HoloMap.API` from Elixir: it queues correctly against the style's
readiness, which a raw handle does not.
