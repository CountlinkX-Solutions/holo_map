# Events

MapLibre events come back as ordinary Hologram actions.

## Handler syntax

Event props accept the same shapes Hologram's own longhand event bindings do:

```elixir
# Bare action name, dispatched to the page.
on_click={:parcel_clicked}

# Longhand, when the handler lives on a component rather than the page.
on_click={%{action: :parcel_clicked, target: "sidebar"}}

# With static params merged into the payload.
on_click={%{action: :parcel_clicked, target: "sidebar", params: %{layer: "parcels"}}}
```

A keyword list works wherever a map does. An unset handler attaches no MapLibre
listener at all, so an event prop can be driven from state:

```elixir
on_click={if @selectable do :parcel_clicked end}
```

## Targets

`target` is a component cid, `"page"`, or `"layout"`. It defaults to `"page"`.

That default differs from Hologram's own, which is the closest enclosing
*stateful* component. `HoloMap`'s children are deliberately stateless and have
no `cid`, so there is nothing to fall back to, and silently targeting the
map container would send the action to `HoloMap.Map` rather than to your
handler.

If your handler lives on a stateful component, name it:

```elixir
<HoloMap.Layer.Fill id="parcels" source="parcels"
                    on_click={%{action: :picked, target: "sidebar"}} />
```

## Params

Whatever you supply in `params` is merged **under** the runtime payload, so the
data MapLibre reports always wins over a static value with the same key. Keys
arrive in your handler as atoms, as they do for any Hologram action.

## Payloads

### Map events

`on_load`, `on_click`, `on_dbl_click`, `on_context_menu`, `on_mouse_move`,
`on_move_start`, `on_move_end`, `on_zoom_end`, `on_rotate_end`, `on_pitch_end`,
`on_idle`, `on_error`.

| Key | Type | Notes |
| --- | ---- | ----- |
| `center` | `[lng, lat]` | Camera centre after the event |
| `zoom` | number | |
| `bearing` | number | |
| `pitch` | number | |
| `bounds` | `[[w, s], [e, n]]` | The visible extent |
| `lng_lat` | `[lng, lat]` | Pointer events only |
| `point` | `[x, y]` | Pointer events only, in pixels |
| `error` | map | `on_error` only. What failed, see below |

```elixir
def action(:map_moved, params, component) do
  put_state(component, :bounds, params.bounds)
end
```

`error` always has a `message`. A failed request (a style, a tile, a sprite)
adds its HTTP `status` and `url`, and an error a source reported adds the
source's `source_id`:

```elixir
def action(:map_failed, %{error: %{source_id: "dem"} = error}, component) do
  put_state(component, :notice, "Elevation tiles are unavailable: #{error.message}")
end

def action(:map_failed, params, component) do
  put_state(component, :notice, params.error.message)
end
```

### Layer events

`on_click`, `on_dbl_click`, `on_context_menu`, `on_mouse_enter`,
`on_mouse_leave`, `on_mouse_move`, `on_mouse_down`, `on_mouse_up`,
`on_touch_start`, `on_touch_end`.

| Key | Type | Notes |
| --- | ---- | ----- |
| `layer` | string | The layer's id |
| `lng_lat` | `[lng, lat]` | |
| `point` | `[x, y]` | In pixels |
| `features` | list | The features under the pointer |

Each feature carries `id`, `source`, `source_layer`, `properties` and
`geometry`. MapLibre's own feature objects hold back-references to their source
and tile which cannot cross into Elixir, so only the actionable parts are
carried over.

> #### Every key is an atom, all the way down {: .info}
>
> Hologram converts JavaScript object keys to atoms when an action's params
> cross the boundary, and it does so **recursively**. A feature therefore
> arrives like this:
>
> ```elixir
> %{
>   id: 0,
>   source: "cities",
>   source_layer: nil,
>   properties: %{name: "Santo Domingo", population: 2_908_000},
>   geometry: %{type: "Point", coordinates: [-69.93, 18.48]}
> }
> ```
>
> Your own GeoJSON property names are part of that: a property written as
> `"parcel_id"` in the data is matched as `%{parcel_id: id}`. Matching with
> string keys silently fails. The clause simply does not match, and a `case`
> with a catch-all falls through without an error.

```elixir
def action(:parcel_clicked, params, component) do
  case params.features do
    [%{properties: %{parcel_id: id}} | _rest] -> put_state(component, :selected, id)
    [] -> put_state(component, :selected, nil)
  end
end
```

`features` is a list because layers overlap; it is empty for a click on empty
space when the event is bound to the map rather than a layer. Match on it rather
than assuming a head.

### Popup events

`on_open`, `on_close`. Neither carries a payload.

`on_close` fires for every close, including the ones MapLibre performs without
asking: the close button, a click on the map (`close_on_click` is on by
default) and a camera move. Handle it by clearing whatever state opened the
popup. Otherwise the component still believes the popup is open, and clicking
the same feature again re-renders nothing.

```elixir
def action(:selection_cleared, _params, component) do
  put_state(component, :selected, nil)
end
```

### Marker events

`on_click`, `on_drag_start`, `on_drag`, `on_drag_end`.

| Key | Type | Notes |
| --- | ---- | ----- |
| `lng_lat` | `[lng, lat]` | For drag events, where the marker has been moved to |

```elixir
def action(:pin_moved, params, component) do
  [lng, lat] = params.lng_lat
  put_state(component, :coords, {lng, lat})
end
```

`on_drag` fires on every pointer move, and writing the position back into state
from it is safe: the value going back is the one MapLibre just reported, so the
`setLngLat` the reconciler performs is a no-op and the marker stays locked to
the cursor. Prefer `on_drag_end` when only the final position matters, since there is
no reason to re-render on every frame for a value nothing reads until the drag
ends.

## Hover styling

The usual pattern needs feature ids, which GeoJSON features often lack. Set
`generate_id` on the source, or point `promote_id` at a property that is already
unique:

```elixir
<HoloMap.Source.GeoJSON id="parcels" data={@parcels} generate_id />

<HoloMap.Layer.Fill
  id="parcels-fill"
  source="parcels"
  paint={%{fill_opacity: ["case", ["boolean", ["feature-state", "hover"], false], 0.8, 0.35]}}
  on_mouse_move={:parcel_hover}
  on_mouse_leave={:parcel_unhover}
/>
```

```elixir
def action(:parcel_hover, params, component) do
  case params.features do
    [%{id: id} | _rest] ->
      clear_hover(component)
      HoloMap.API.set_feature_state("explorer", %{source: "parcels", id: id}, %{hover: true})
      put_state(component, :hovered, id)

    [] ->
      component
  end
end
```

## What is not reported back

A camera move the reconciler itself made, because you changed `center` or
`zoom` from state, does **not** fire `on_move_end`. Only a move the user or the
imperative API caused does.

Without that, writing the camera from state would echo straight back into an
action: a feedback loop at best, and at worst an action arriving on a page that
has already changed. If you need to know when your own camera assignment
settled, you already do: it is the state change that caused it.

## Ordering and timing

`Hologram.dispatchAction` is asynchronous. An event dispatched at the moment a
navigation begins can execute after the new page has mounted, which is why
`HoloMap` refuses to dispatch from a map whose container has gone stale. Your
handlers do not need to defend against this, but it is worth knowing why an
action can appear to arrive late.
