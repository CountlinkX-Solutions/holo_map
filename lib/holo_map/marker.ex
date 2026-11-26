defmodule HoloMap.Marker do
  @moduledoc """
  A pin at a coordinate, rendered as a DOM element above the map.

      <HoloMap.Marker id="office" lng_lat={{-70.66, 19.45}} color="#ef4444" />

  With custom markup, given as slot content:

      <HoloMap.Marker id="office" lng_lat={{-70.66, 19.45}} on_click={:office_clicked}>
        <div class="rounded-full bg-white px-2 py-1 shadow">Head office</div>
      </HoloMap.Marker>

  ## Markers versus symbol layers

  A marker is a DOM node. That makes it easy to style with your own CSS and
  cheap to reason about, and expensive at scale. A few dozen is comfortable, a
  few thousand is not. Past that, put the points in a
  `HoloMap.Source.GeoJSON` and draw them with `HoloMap.Layer.Circle` or
  `HoloMap.Layer.Symbol`, which render on the GPU. `HoloMap.Image` is what lets
  that symbol layer use an icon of your own.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** Identity across re-renders |
  | `lng_lat` | `{lng, lat}` | **Required.** Where the marker sits |
  | `color` | string | Fill colour of the default pin. Ignored when slot content is given |
  | `scale` | number | Size multiplier for the default pin |
  | `draggable` | boolean | Let the user move the marker |
  | `rotation` | number | Rotation in degrees |
  | `offset` | `[x, y]` | Pixel offset from the anchor point |
  | `anchor` | string | `"center"`, `"top"`, `"bottom"`, `"left"`, `"right"` and the corners |
  | `pitch_alignment` / `rotation_alignment` | string | `"map"`, `"viewport"` or `"auto"` |
  | `opacity` | string | CSS opacity |
  | `class_name` | string | Extra classes on the marker element |
  | `popup_html` | string | Attach a popup that opens when the marker is clicked |
  | `popup_options` | map | Options for that popup, in `HoloMap.Popup`'s vocabulary. String keys reach MapLibre unchanged |


  > #### Raw HTML must arrive through an expression {: .info}
  >
  > Hologram HTML-escapes literal text attributes before they ever reach a
  > component, so `popup_html="<b>hi</b>"` written directly in a template
  > arrives as the *characters* `<b>hi</b>` and renders as visible text. Pass
  > it as an expression instead (`popup_html={@html}`, or a value from state)
  > and the markup survives. Slot content has no such caveat.

  ## Events

  `on_click`, `on_drag_start`, `on_drag`, `on_drag_end`. Handlers receive
  `lng_lat`, which for the drag events is the position the marker moved to:

      def action(:pin_moved, params, component) do
        [lng, lat] = params.lng_lat
        put_state(component, coords: {lng, lat})
      end

  ### Dragging

  Set `draggable` and the user can move the marker. `on_drag_start` fires once,
  `on_drag` on every pointer move, `on_drag_end` once at the finish.

  Writing the position back into state from `on_drag` is safe, and is the usual
  way to keep a coordinate readout live. It looks like it should not be: each
  event is a state update, a re-render, and a `setLngLat` back into the marker
  MapLibre is in the middle of dragging. It works because the value going back
  is the one MapLibre just reported, so the write is a no-op. The marker stays
  locked to the cursor, measured at zero pixels of drift.

      <HoloMap.Marker id="pin" lng_lat={@pin} draggable
                      on_drag={:pin_moved} on_drag_end={:pin_settled} />

  Use `on_drag_end` alone when only the final position matters; there is no
  reason to re-render on every frame for a value nothing reads until the drag
  is over.

  > #### Slot content is cloned {: .warning}
  >
  > MapLibre moves a marker's element into its own overlay container. Handing
  > it the node Hologram rendered would take that node out from under the
  > virtual DOM and corrupt the next patch, so `HoloMap` gives MapLibre a
  > **clone** instead. The markup renders and restyles normally, but Hologram
  > event bindings inside the slot never fire. Use `on_click` on the marker
  > itself. See the [Limitations guide](limitations.html).
  """

  use HoloMap.Def

  @keys [
    color: "color",
    scale: "scale",
    draggable: "draggable",
    rotation: "rotation",
    offset: "offset",
    anchor: "anchor",
    pitch_alignment: "pitchAlignment",
    rotation_alignment: "rotationAlignment",
    opacity: "opacity",
    class_name: "className",
    click_tolerance: "clickTolerance",
    subpixel_positioning: "subpixelPositioning"
  ]

  prop :id, :string, required: true
  prop :lng_lat, :any, required: true
  prop :color, :string, default: nil
  prop :scale, :any, default: nil
  prop :draggable, :any, default: nil
  prop :rotation, :any, default: nil
  prop :offset, :list, default: nil
  prop :anchor, :string, default: nil
  prop :pitch_alignment, :string, default: nil
  prop :rotation_alignment, :string, default: nil
  prop :opacity, :string, default: nil
  prop :class_name, :string, default: nil
  prop :click_tolerance, :any, default: nil
  prop :subpixel_positioning, :any, default: nil
  prop :popup_html, :string, default: nil
  prop :popup_options, :map, default: nil

  prop :on_click, :any, default: nil
  prop :on_drag_start, :any, default: nil
  prop :on_drag, :any, default: nil
  prop :on_drag_end, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="marker"
      data-hm-key={@id}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Marker.build(%{
        lng_lat: @lng_lat,
        color: @color,
        scale: @scale,
        draggable: @draggable,
        rotation: @rotation,
        offset: @offset,
        anchor: @anchor,
        pitch_alignment: @pitch_alignment,
        rotation_alignment: @rotation_alignment,
        opacity: @opacity,
        class_name: @class_name,
        click_tolerance: @click_tolerance,
        subpixel_positioning: @subpixel_positioning,
        popup_html: @popup_html,
        popup_options: @popup_options
      })}
      data-hm-events={HoloMap.Def.events(
        click: @on_click,
        dragstart: @on_drag_start,
        drag: @on_drag,
        dragend: @on_drag_end
      )}
    ><div data-hm-content><slot /></div></div>
    """
  end

  @doc false
  @spec build(map()) :: String.t()
  def build(props) do
    props
    |> HoloMap.Spec.booleans([:draggable, :subpixel_positioning])
    |> HoloMap.Spec.take(@keys)
    |> Map.put("lngLat", HoloMap.Spec.lng_lat(props.lng_lat))
    |> Map.put("popup", popup(props))
    |> HoloMap.Def.spec()
  end

  defp popup(%{popup_html: nil}), do: nil

  defp popup(props) do
    %{"html" => props.popup_html, "options" => HoloMap.Popup.options(props.popup_options || %{})}
  end
end
