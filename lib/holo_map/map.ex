defmodule HoloMap.Map do
  @moduledoc """
  The map container. Everything else in `HoloMap` goes inside one.

      <HoloMap.Map cid="explorer" style={@style_url} center={{-70.66, 19.45}} zoom={11}>
        <HoloMap.Source.GeoJSON id="parcels" data={@parcels} />
        <HoloMap.Layer.Fill id="parcels-fill" source="parcels" paint={%{fill_color: "#3b82f6"}} />
      </HoloMap.Map>

  ## The cid is the map's identity

  `cid` is Hologram's component id, and `HoloMap` uses it as the map's name
  throughout: the DOM container is `hm--<cid>`, the browser registry is keyed by
  it, and it is the first argument to every `HoloMap.API` function. One
  identifier, no second `id` prop to keep in sync.

  A `cid` is mandatory. Hologram only runs `init/3`, and therefore only allows
  actions, on stateful components, and the map needs an action to boot.

  ## Sizing

  A map with no height renders as a zero-pixel box, which is the single most
  common way to end up staring at a blank page. `height` defaults to `"400px"`
  for that reason. Pass `class` instead when the size comes from your own CSS,
  and set `height={nil}` to opt out of the inline style entirely.

  ## The worker URL

  MapLibre parses tiles in a Web Worker that it builds by importing
  `maplibre-gl-worker.mjs`, resolved relative to its own module URL. Hologram
  bundles MapLibre into a page bundle under `/hologram/`, so that resolution
  lands on a file which is not there, and the failure happens inside a worker,
  where nothing reports it. The symptom is a map that renders its background,
  logs nothing, and never draws a single tile.

  `HoloMap` sets the URL explicitly to avoid that. The default assumes the
  application serves `maplibre-gl-worker.mjs` and `maplibre-gl-shared.mjs` from
  `/assets/`; the [Installation guide](installation.html) has the copy step, and
  `worker_url` overrides the path if they live elsewhere.

  ## Declarative camera versus animated camera

  `center`, `zoom`, `bearing` and `pitch` are state. Changing one jumps the
  camera there, and panning the map by hand does *not* write back into them:
  the props describe where the application thinks the camera should be, not
  where the user dragged it. Nothing re-renders while the user interacts, so
  there is no fight between the two.

  When a camera move is an *event* rather than a value, such as flying to a
  search result, use `HoloMap.API.fly_to/2` and leave the props alone.


  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `style` | string or map | **Required.** Style URL or inline style object |
  | `center` | `{lng, lat}` | Camera centre |
  | `zoom` / `bearing` / `pitch` | number | Camera attitude |
  | `min_zoom` / `max_zoom` / `min_pitch` / `max_pitch` | number | Camera constraints |
  | `max_bounds` | bounds | Pan constraint, in any shape `HoloMap.Spec.bounds/1` accepts |
  | `interactive` | boolean | `false` for a static, non-navigable map |
  | `hash` | boolean | Sync the camera to the URL fragment |
  | `attribution_control` | boolean | MapLibre's built-in attribution. See `HoloMap.Control.Attribution` to place it yourself |
  | `cooperative_gestures` | boolean | Require ctrl/⌘ to scroll-zoom, so the page still scrolls |
  | `drag_rotate` / `drag_pan` / `scroll_zoom` / `double_click_zoom` / `box_zoom` / `keyboard` / `touch_zoom_rotate` | boolean | Individual interaction handlers |
  | `antialias` / `pixel_ratio` / `fade_duration` / `render_world_copies` / `bearing_snap` / `track_resize` / `pitch_with_rotate` / `max_tile_cache_size` / `local_ideograph_font_family` / `validate_style` / `locale` | various | Passed straight through to MapLibre |
  | `options` | map | Raw MapLibre constructor options, merged last. Keys must be MapLibre's own camelCase names: `options={%{"maxCanvasSize" => [2048, 2048]}}` |
  | `worker_url` | string | Where the application serves `maplibre-gl-worker.mjs`. Default `"/assets/maplibre-gl-worker.mjs"`. See below |
  | `class` | string | CSS classes for the wrapper element |
  | `height` / `width` | string | Inline size for the canvas. `nil` opts out and leaves sizing to CSS |

  ### Event props

  `on_load`, `on_click`, `on_dbl_click`, `on_context_menu`, `on_mouse_move`,
  `on_move_start`, `on_move_end`, `on_zoom_end`, `on_rotate_end`,
  `on_pitch_end`, `on_idle`, `on_error`.

  ## Events

  Handlers receive a payload with `center`, `zoom`, `bearing`, `pitch` and
  `bounds`, plus `lng_lat` and `point` for pointer events:

      def action(:map_moved, params, component) do
        put_state(component, :bounds, params.bounds)
      end

  See `HoloMap.Event` for the handler syntax and the [Events
  guide](events.html) for the full payload reference.
  """

  use Hologram.Component

  alias HoloMap.Def
  alias HoloMap.Runtime
  alias HoloMap.Spec

  @boolean_props [
    :interactive,
    :hash,
    :attribution_control,
    :antialias,
    :cooperative_gestures,
    :drag_rotate,
    :drag_pan,
    :scroll_zoom,
    :double_click_zoom,
    :box_zoom,
    :keyboard,
    :touch_zoom_rotate,
    :pitch_with_rotate,
    :render_world_copies,
    :track_resize,
    :validate_style
  ]

  @option_keys [
    style: "style",
    center: "center",
    zoom: "zoom",
    bearing: "bearing",
    pitch: "pitch",
    min_zoom: "minZoom",
    max_zoom: "maxZoom",
    min_pitch: "minPitch",
    max_pitch: "maxPitch",
    max_bounds: "maxBounds",
    interactive: "interactive",
    hash: "hash",
    attribution_control: "attributionControl",
    antialias: "antialias",
    cooperative_gestures: "cooperativeGestures",
    drag_rotate: "dragRotate",
    drag_pan: "dragPan",
    scroll_zoom: "scrollZoom",
    double_click_zoom: "doubleClickZoom",
    box_zoom: "boxZoom",
    keyboard: "keyboard",
    touch_zoom_rotate: "touchZoomRotate",
    pitch_with_rotate: "pitchWithRotate",
    render_world_copies: "renderWorldCopies",
    fade_duration: "fadeDuration",
    bearing_snap: "bearingSnap",
    track_resize: "trackResize",
    max_tile_cache_size: "maxTileCacheSize",
    local_ideograph_font_family: "localIdeographFontFamily",
    pixel_ratio: "pixelRatio",
    validate_style: "validateStyle",
    locale: "locale",
    worker_url: "workerUrl"
  ]

  prop :style, :any, required: true
  prop :center, :any, default: nil

  prop :zoom, :any, default: nil
  prop :bearing, :any, default: nil
  prop :pitch, :any, default: nil
  prop :min_zoom, :any, default: nil
  prop :max_zoom, :any, default: nil
  prop :min_pitch, :any, default: nil
  prop :max_pitch, :any, default: nil

  prop :max_bounds, :any, default: nil

  prop :interactive, :any, default: nil
  prop :hash, :any, default: nil
  prop :attribution_control, :any, default: nil
  prop :antialias, :any, default: nil
  prop :cooperative_gestures, :any, default: nil
  prop :drag_rotate, :any, default: nil
  prop :drag_pan, :any, default: nil
  prop :scroll_zoom, :any, default: nil
  prop :double_click_zoom, :any, default: nil
  prop :box_zoom, :any, default: nil
  prop :keyboard, :any, default: nil
  prop :touch_zoom_rotate, :any, default: nil
  prop :pitch_with_rotate, :any, default: nil
  prop :render_world_copies, :any, default: nil
  prop :fade_duration, :any, default: nil
  prop :bearing_snap, :any, default: nil
  prop :track_resize, :any, default: nil
  prop :max_tile_cache_size, :any, default: nil
  prop :local_ideograph_font_family, :any, default: nil
  prop :pixel_ratio, :any, default: nil
  prop :validate_style, :any, default: nil
  prop :locale, :any, default: nil
  prop :worker_url, :string, default: "/assets/maplibre-gl-worker.mjs"

  prop :options, :map, default: %{}
  prop :class, :string, default: nil
  prop :height, :string, default: "400px"
  prop :width, :string, default: "100%"

  prop :on_load, :any, default: nil
  prop :on_click, :any, default: nil
  prop :on_dbl_click, :any, default: nil
  prop :on_context_menu, :any, default: nil
  prop :on_mouse_move, :any, default: nil
  prop :on_move_start, :any, default: nil
  prop :on_move_end, :any, default: nil
  prop :on_zoom_end, :any, default: nil
  prop :on_rotate_end, :any, default: nil
  prop :on_pitch_end, :any, default: nil
  prop :on_idle, :any, default: nil
  prop :on_error, :any, default: nil

  @impl Hologram.Component
  def init(props, component, server) do
    {mount(props, component), server}
  end

  @impl Hologram.Component
  def init(props, component) do
    mount(props, component)
  end

  # Booting has to happen in an action: Hologram's JS interop is a no-op during
  # server-side rendering and inside `init`, so the map can only be constructed
  # once the client runtime is live. `put_action/2` is the supported way to
  # schedule that for mount time.
  defp mount(props, component) do
    component
    |> put_state(:map_cid, props.cid)
    |> put_context(Def.context_key(), props.cid)
    |> put_action(:__holo_map_boot__)
  end

  @impl Hologram.Component
  def action(:__holo_map_boot__, _params, component) do
    Runtime.boot(component.state.map_cid)
    component
  end

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div class={@class}>
      <div id={"hm--" <> @cid} style={HoloMap.Map.canvas_style(@height, @width)}></div>
      <div id={"hm--" <> @cid <> "--defs"} hidden>
        <div
          data-hm="map"
          data-hm-key="map"
          data-hm-map={@cid}
          data-hm-spec={HoloMap.Map.__spec__(%{
            style: @style,
            center: @center,
            zoom: @zoom,
            bearing: @bearing,
            pitch: @pitch,
            min_zoom: @min_zoom,
            max_zoom: @max_zoom,
            min_pitch: @min_pitch,
            max_pitch: @max_pitch,
            max_bounds: @max_bounds,
            interactive: @interactive,
            hash: @hash,
            attribution_control: @attribution_control,
            antialias: @antialias,
            cooperative_gestures: @cooperative_gestures,
            drag_rotate: @drag_rotate,
            drag_pan: @drag_pan,
            scroll_zoom: @scroll_zoom,
            double_click_zoom: @double_click_zoom,
            box_zoom: @box_zoom,
            keyboard: @keyboard,
            touch_zoom_rotate: @touch_zoom_rotate,
            pitch_with_rotate: @pitch_with_rotate,
            render_world_copies: @render_world_copies,
            fade_duration: @fade_duration,
            bearing_snap: @bearing_snap,
            track_resize: @track_resize,
            max_tile_cache_size: @max_tile_cache_size,
            local_ideograph_font_family: @local_ideograph_font_family,
            pixel_ratio: @pixel_ratio,
            validate_style: @validate_style,
            locale: @locale,
            worker_url: @worker_url,
            options: @options
          })}
          data-hm-events={HoloMap.Def.events(
            load: @on_load,
            click: @on_click,
            dblclick: @on_dbl_click,
            contextmenu: @on_context_menu,
            mousemove: @on_mouse_move,
            movestart: @on_move_start,
            moveend: @on_move_end,
            zoomend: @on_zoom_end,
            rotateend: @on_rotate_end,
            pitchend: @on_pitch_end,
            idle: @on_idle,
            error: @on_error
          )}
        ></div>
        <slot />
      </div>
    </div>
    """
  end

  @doc false
  @spec canvas_style(String.t() | nil, String.t() | nil) :: String.t() | nil
  def canvas_style(nil, nil), do: nil
  def canvas_style(height, nil), do: "height:#{height}"
  def canvas_style(nil, width), do: "width:#{width}"
  def canvas_style(height, width), do: "height:#{height};width:#{width}"

  @doc false
  @spec __spec__(map()) :: String.t()
  def __spec__(props) do
    props
    |> Spec.booleans(@boolean_props)
    |> Map.put(:center, Spec.lng_lat(props.center))
    |> Map.put(:max_bounds, Spec.bounds(props.max_bounds))
    |> Spec.take(@option_keys)
    |> Map.merge(props.options || %{})
    |> Def.spec()
  end
end
