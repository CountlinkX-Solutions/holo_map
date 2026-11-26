defmodule HoloMap.Popup do
  @moduledoc """
  A tooltip anchored to a coordinate.

      <HoloMap.Popup id="details" lng_lat={@selected_coords}>
        <h3>{@selected.name}</h3>
        <p>{@selected.address}</p>
      </HoloMap.Popup>

  A popup declared here is *open*. Closing it means not rendering it, which is
  ordinary conditional rendering:

      {%if @selected}
        <HoloMap.Popup id="details" lng_lat={@selected.coords}>
          <h3>{@selected.name}</h3>
        </HoloMap.Popup>
      {/if}

  That is the whole state model. There is no imperative open/close, because
  "which popup is open" is application state and belongs in your component.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** Identity across re-renders |
  | `lng_lat` | `{lng, lat}` | **Required.** Where the popup points |
  | `html` | string | Content as an HTML string, instead of slot content |
  | `close_button` | boolean | Show MapLibre's own close button |
  | `close_on_click` | boolean | Close when the map is clicked |
  | `close_on_move` | boolean | Close when the camera moves |
  | `anchor` | string | Which side of the popup touches the coordinate |
  | `offset` | number, `[x, y]` or map | Pixel offset from the anchor |
  | `class_name` | string | Extra classes on the popup element |
  | `max_width` | string | CSS max-width, default `"240px"` |
  | `focus_after_open` | boolean | Move keyboard focus into the popup |
  | `subpixel_positioning` | boolean | Position on fractional pixels |


  > #### Raw HTML must arrive through an expression {: .info}
  >
  > Hologram HTML-escapes literal text attributes before they ever reach a
  > component, so `html="<b>hi</b>"` written directly in a template
  > arrives as the *characters* `<b>hi</b>` and renders as visible text. Pass
  > it as an expression instead (`html={@html}`, or a value from state)
  > and the markup survives. Slot content has no such caveat.

  ## Closing with the built-in button

  MapLibre closes a popup on its own for three reasons: the close button, a
  click on the map (`close_on_click`, on by default) and a camera move
  (`close_on_move`). None of them go through your state, so without help the
  component that rendered the popup still believes it is open, and clicking the
  same thing again changes nothing, re-renders nothing, and the popup never
  comes back.

  `on_close` is what closes that gap. Handle it by clearing whatever state
  opened the popup, and the declaration matches reality again:

      {%if @selected}
        <HoloMap.Popup id="details" lng_lat={@selected.coords} on_close={:selection_cleared}>
          <h3>{@selected.name}</h3>
        </HoloMap.Popup>
      {/if}

      def action(:selection_cleared, _params, component) do
        put_state(component, :selected, nil)
      end

  If you would rather not handle it, set `close_button={false}` and
  `close_on_click={false}` so the only way to close the popup is through your
  own state.

  A changed declaration always re-asserts itself: if the props change while
  MapLibre has the popup closed, it reopens. Selecting a different feature
  therefore works whether or not the previous popup was dismissed.

  ## Events

  `on_open` fires when the popup is added to the map, `on_close` when it leaves
  it, including every close MapLibre performs on its own. Neither carries a
  payload.

  > #### Slot content is cloned {: .warning}
  >
  > Like `HoloMap.Marker`, popup content reaches MapLibre as an HTML clone, so
  > Hologram event bindings inside the slot do not fire. Put interactive
  > controls outside the map and drive them from state instead. See the
  > [Limitations guide](limitations.html).
  """

  use HoloMap.Def

  @options [
    close_button: "closeButton",
    close_on_click: "closeOnClick",
    close_on_move: "closeOnMove",
    anchor: "anchor",
    offset: "offset",
    class_name: "className",
    max_width: "maxWidth",
    focus_after_open: "focusAfterOpen",
    subpixel_positioning: "subpixelPositioning"
  ]

  @option_names Keyword.keys(@options)

  @keys @options ++ [html: "html"]

  @booleans [
    :close_button,
    :close_on_click,
    :close_on_move,
    :focus_after_open,
    :subpixel_positioning
  ]

  prop :id, :string, required: true
  prop :lng_lat, :any, required: true
  prop :html, :string, default: nil
  prop :close_button, :any, default: nil
  prop :close_on_click, :any, default: nil
  prop :close_on_move, :any, default: nil
  prop :anchor, :string, default: nil
  prop :offset, :any, default: nil
  prop :class_name, :string, default: nil
  prop :max_width, :string, default: nil
  prop :focus_after_open, :any, default: nil
  prop :subpixel_positioning, :any, default: nil

  prop :on_close, :any, default: nil
  prop :on_open, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="popup"
      data-hm-key={@id}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Popup.build(%{
        lng_lat: @lng_lat,
        html: @html,
        close_button: @close_button,
        close_on_click: @close_on_click,
        close_on_move: @close_on_move,
        anchor: @anchor,
        offset: @offset,
        class_name: @class_name,
        max_width: @max_width,
        focus_after_open: @focus_after_open,
        subpixel_positioning: @subpixel_positioning
      })}
      data-hm-events={HoloMap.Def.events(close: @on_close, open: @on_open)}
    ><div data-hm-content><slot /></div></div>
    """
  end

  @doc false
  @spec build(map()) :: String.t()
  def build(props) do
    props
    |> HoloMap.Spec.booleans(@booleans)
    |> HoloMap.Spec.take(@keys)
    |> Map.put("lngLat", HoloMap.Spec.lng_lat(props.lng_lat))
    |> HoloMap.Def.spec()
  end

  # MapLibre popup options from a map in this component's vocabulary, which is
  # what `HoloMap.Marker`'s `popup_options` takes. The atom keys this component
  # knows go through its key table and boolean coercion. Any other key passes
  # through as given, so string keys remain the escape hatch they are elsewhere.
  @doc false
  @spec options(map()) :: map()
  def options(options) when is_map(options) do
    converted =
      options
      |> HoloMap.Spec.booleans(@booleans)
      |> HoloMap.Spec.take(@options)

    Enum.reduce(options, converted, fn
      {key, _value}, acc when key in @option_names -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
