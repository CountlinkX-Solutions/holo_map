# Getting started

This walks from an empty map to one that shows your own data, restyles it from
state, and reports clicks back as Hologram actions. It assumes
[Installation](installation.html) is done.

## A map

```elixir
defmodule MyAppWeb.ExplorerPage do
  use Hologram.Page

  route "/explorer"
  layout MyAppWeb.Layout

  def init(_params, component, _server) do
    put_state(component, :style, "https://demotiles.maplibre.org/style.json")
  end

  def template do
    ~HOLO"""
    <HoloMap.Map cid="explorer" style={@style} center={{-70.66, 19.45}} zoom={11} height="500px">
      <HoloMap.Control.Navigation position="top-right" />
      <HoloMap.Control.Scale position="bottom-left" />
    </HoloMap.Map>
    """
  end
end
```

Three things are worth noticing.

`cid` is the map's name everywhere: the DOM container, the browser registry, and
the first argument to every `HoloMap.API` call. There is no second `id` prop.

`style` is required, because MapLibre cannot render without one. In production this is
your own tile server or a hosted style; `demotiles.maplibre.org` is a public
world map that needs no key, which makes it useful for exactly this.

`height` defaults to `"500px"` here but `"400px"` in general, because a map with
no height renders as a zero-pixel box. Pass `class` and set `height={nil}` when
your own CSS sizes it.

## Adding your data

A source says where data comes from; layers say how it looks. One source
routinely feeds several layers:

```elixir
<HoloMap.Map cid="explorer" style={@style} center={{-70.66, 19.45}} zoom={11}>
  <HoloMap.Source.GeoJSON id="parcels" data={@parcels} generate_id />

  <HoloMap.Layer.Fill
    id="parcels-fill"
    source="parcels"
    paint={%{fill_color: "#3b82f6", fill_opacity: 0.35}}
  />

  <HoloMap.Layer.Line
    id="parcels-outline"
    source="parcels"
    paint={%{line_color: "#1e40af", line_width: 1}}
  />
</HoloMap.Map>
```

`data` is a plain Elixir map in GeoJSON shape. Build it wherever you build
anything else, typically a command, since that is what runs on the server:

```elixir
def init(_params, component, _server) do
  component
  |> put_state(style: @style_url, parcels: empty_collection())
  |> put_command(:load_parcels)
end

def command(:load_parcels, _params, server) do
  put_action(server, :parcels_loaded, parcels: MyApp.Parcels.as_geojson())
end

def action(:parcels_loaded, params, component) do
  put_state(component, :parcels, params.parcels)
end
```

Changing `data` later is the one source update that costs nothing structurally:
MapLibre swaps the features in place with `setData`, and the layers above it are
untouched.

## Property names

Paint and layout properties may be written as Elixir atoms and are dasherized on
the way out, so `fill_color` becomes `"fill-color"`. String keys pass through
verbatim, which is the escape hatch for anything this library has not caught up
with:

```elixir
paint={%{"fill-color" => "#f00", "some-new-property" => 1}}
```

Expressions are ordinary Elixir lists:

```elixir
paint={%{
  circle_radius: ["interpolate", ["linear"], ["get", "population"], 300_000, 6, 10_000_000, 26]
}}
```

## Making it react to state

Nothing special is required. Props are props:

```elixir
def template do
  ~HOLO"""
  <button $click={:toggle_colour}>Toggle</button>

  <HoloMap.Map cid="explorer" style={@style} center={{-70.66, 19.45}} zoom={11}>
    <HoloMap.Source.GeoJSON id="parcels" data={@parcels} />
    <HoloMap.Layer.Fill id="parcels-fill" source="parcels"
                        paint={%{fill_color: @colour}} filter={@filter} />
  </HoloMap.Map>
  """
end

def action(:toggle_colour, _params, component) do
  put_state(component, :colour, if(component.state.colour == "#3b82f6", do: "#ef4444", else: "#3b82f6"))
end
```

That reaches MapLibre as `setPaintProperty`. The layer is not rebuilt, the
canvas is not touched, and nothing flickers. Changing `filter` likewise becomes
`setFilter`.

The same applies to visibility, zoom ranges, and the map's own camera. See
[Architecture](architecture.html) for which changes are cheap and which force a
rebuild.

## Getting events back

Add an event prop; write an ordinary action:

```elixir
<HoloMap.Layer.Fill
  id="parcels-fill"
  source="parcels"
  paint={%{fill_color: @colour}}
  on_click={:parcel_clicked}
  on_mouse_enter={:parcel_hovered}
/>
```

```elixir
def action(:parcel_clicked, params, component) do
  case params.features do
    [%{properties: %{parcel_id: id}} | _rest] -> put_state(component, :selected, id)
    [] -> component
  end
end
```

`params.features` holds the features under the pointer, each with `id`,
`source`, `source_layer`, `properties` and `geometry`. Every key arrives as an
**atom**, nested ones included, so a GeoJSON property named `parcel_id` is
matched as `%{parcel_id: id}`, not `%{"parcel_id" => id}`. The full payload
reference is in [Events](events.html).

## Icons

`icon_image` on a symbol layer names an image; it does not fetch one. If the
name is not in the style's own sprite, and plenty of styles ship none, nothing
draws, and nothing reports why. Register your own with `HoloMap.Image`:

```elixir
<HoloMap.Image id="pin" url="/icons/pin.png" />

<HoloMap.Layer.Symbol
  id="stops"
  source="stops"
  layout={%{icon_image: "pin", icon_size: 0.5, icon_allow_overlap: true}}
/>
```

Order does not matter: the layer starts drawing once the image arrives. The same
applies to `fill_pattern` and `line_pattern`.

## Showing a popup

A popup in the template is open; closing it means not rendering it:

```elixir
{%if @selected}
  <HoloMap.Popup id="details" lng_lat={@selected.coords}>
    <h3>{@selected.name}</h3>
  </HoloMap.Popup>
{/if}
```

There is no imperative open/close, because "which popup is open" is application
state.

## Flying somewhere

Setting `center` and `zoom` from state jumps the camera there. That is right
when the camera reflects state, and wrong when it is a response to an event:
re-rendering the same centre twice should not re-animate. For that, use the
imperative API from inside an action:

```elixir
def action(:show_result, params, component) do
  HoloMap.API.fly_to("explorer", center: {params.lng, params.lat}, zoom: 16, duration: 1_500)
  put_state(component, :selected, params.id)
end
```

See [Imperative API](imperative-api.html) for the full list and when to reach
for it.

## Where to go next

- [Architecture](architecture.html): how a prop change becomes a MapLibre call, and what that costs
- [Events](events.html): handler syntax, targets and every payload
- [Limitations](limitations.html): the things that do not work, and why
- `HoloMap`: the component index, and every module's own docs
