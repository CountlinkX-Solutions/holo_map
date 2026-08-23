defmodule HoloMap.API do
  @moduledoc """
  Imperative commands for things that are not state.

  Most of a map belongs in component props: which layers exist, how they are
  painted, what the camera is looking at. Some of it does not. "Fly to the
  result the user just picked" is an event, not a value. Re-rendering the same
  centre twice should not re-animate, and animating is the whole point.

  These functions are for that second category. Call them from an action:

      def action(:show_parcel, params, component) do
        HoloMap.API.fly_to("explorer", center: {params.lng, params.lat}, zoom: 17)
        put_state(component, :selected, params.id)
      end

  The first argument is always the map's `cid`, the same string given to
  `HoloMap.Map`.

  > #### Actions only {: .warning}
  >
  > These calls compile to no-ops on the server. They work in `action/3` and in
  > functions an action reaches; they do nothing in `init/3` or `command/3`.

  ## Choosing between this and props

  | Situation | Use |
  | --------- | --- |
  | The camera reflects application state | `HoloMap.Map`'s `center`/`zoom` props |
  | The camera should animate in response to an event | `fly_to/2`, `ease_to/2` |
  | A layer's paint reflects state | `HoloMap.Layer.*`'s `paint` prop |
  | A one-off highlight that should not survive a re-render | `set_paint_property/4` |

  Anything set imperatively is overwritten the next time the declarative
  specification for that object changes. The reconciler treats the rendered
  props as the source of truth.
  """

  alias HoloMap.Runtime
  alias HoloMap.Spec

  @camera_keys [
    center: "center",
    zoom: "zoom",
    bearing: "bearing",
    pitch: "pitch",
    duration: "duration",
    essential: "essential",
    offset: "offset",
    padding: "padding",
    animate: "animate",
    speed: "speed",
    curve: "curve",
    max_duration: "maxDuration",
    screen_speed: "screenSpeed",
    easing: "easing"
  ]

  @fit_keys [
    padding: "padding",
    max_zoom: "maxZoom",
    linear: "linear",
    duration: "duration",
    offset: "offset",
    bearing: "bearing",
    pitch: "pitch",
    animate: "animate",
    essential: "essential"
  ]

  @doc """
  Animates the camera along a curved flight path.

  Accepts `:center`, `:zoom`, `:bearing`, `:pitch`, `:duration`, `:speed`,
  `:curve`, `:offset`, `:padding`, `:max_duration`, `:essential` and `:animate`.

      HoloMap.API.fly_to("explorer", center: {-70.66, 19.45}, zoom: 14, duration: 1_200)
  """
  @spec fly_to(String.t(), keyword()) :: :ok
  def fly_to(cid, opts) do
    Runtime.call(cid, "flyTo", [camera_options(opts)])
  end

  @doc """
  Animates the camera along a straight path, without the zoom-out arc.

  Takes the same options as `fly_to/2` minus the flight-specific `:speed` and
  `:curve`, which it ignores.
  """
  @spec ease_to(String.t(), keyword()) :: :ok
  def ease_to(cid, opts) do
    Runtime.call(cid, "easeTo", [camera_options(opts)])
  end

  @doc """
  Moves the camera with no animation at all.
  """
  @spec jump_to(String.t(), keyword()) :: :ok
  def jump_to(cid, opts) do
    Runtime.call(cid, "jumpTo", [camera_options(opts)])
  end

  @doc """
  Fits the camera to a bounding box.

  `bounds` accepts any shape `HoloMap.Spec.bounds/1` understands: a pair of
  corners, or a flat `[west, south, east, north]` list.

      HoloMap.API.fit_bounds("explorer", [-71.0, 19.0, -70.0, 20.0], padding: 48)
  """
  @spec fit_bounds(String.t(), term(), keyword()) :: :ok
  def fit_bounds(cid, bounds, opts \\ []) do
    options = opts |> Enum.into(%{}) |> Spec.take(@fit_keys)
    Runtime.call(cid, "fitBounds", [Spec.bounds(bounds), options])
  end

  @doc """
  Recomputes the map's size after its container has been resized.

  MapLibre watches its container, so this is only needed when the container
  changes size without a resize event the browser reports, such as a CSS transition on
  a sidebar, for instance.
  """
  @spec resize(String.t()) :: :ok
  def resize(cid), do: Runtime.call(cid, "resize", [])

  @doc """
  Replaces the whole style.

  Prefer `HoloMap.Map`'s `style` prop; a style swap discards every source and
  layer, and the reconciler re-declares the ones it owns on the next
  `styledata` event.
  """
  @spec set_style(String.t(), String.t() | map()) :: :ok
  def set_style(cid, style), do: Runtime.call(cid, "setStyle", [style])

  @doc """
  Sets a layer's filter, or clears it when `filter` is `nil`.

      HoloMap.API.set_filter("explorer", "parcels-fill", ["==", ["get", "zone"], "R1"])
  """
  @spec set_filter(String.t(), String.t(), list() | nil) :: :ok
  def set_filter(cid, layer_id, filter) do
    Runtime.call(cid, "setFilter", [layer_id, filter])
  end

  @doc """
  Sets one paint property on a layer.

  `property` may be given as an atom in Elixir style (`:fill_color`) or as the
  specification name (`"fill-color"`).
  """
  @spec set_paint_property(String.t(), String.t(), atom() | String.t(), term()) :: :ok
  def set_paint_property(cid, layer_id, property, value) do
    Runtime.call(cid, "setPaintProperty", [layer_id, property_name(property), value])
  end

  @doc """
  Sets one layout property on a layer.

  Useful for toggling visibility without removing the layer:

      HoloMap.API.set_layout_property("explorer", "parcels-fill", :visibility, "none")
  """
  @spec set_layout_property(String.t(), String.t(), atom() | String.t(), term()) :: :ok
  def set_layout_property(cid, layer_id, property, value) do
    Runtime.call(cid, "setLayoutProperty", [layer_id, property_name(property), value])
  end

  @doc """
  Attaches feature state, the mechanism behind hover and selection styling.

  `feature` identifies the feature: `%{source: "parcels", id: 12}`, plus
  `:source_layer` for a vector source.

      HoloMap.API.set_feature_state("explorer", %{source: "parcels", id: id}, %{hover: true})
  """
  @spec set_feature_state(String.t(), map(), map()) :: :ok
  def set_feature_state(cid, feature, state) do
    Runtime.call(cid, "setFeatureState", [feature_ref(feature), state])
  end

  @doc """
  Clears feature state.

  Omit `key` to clear every state entry on the feature.
  """
  @spec remove_feature_state(String.t(), map(), String.t() | nil) :: :ok
  def remove_feature_state(cid, feature, key \\ nil) do
    args =
      case key do
        nil -> [feature_ref(feature)]
        key -> [feature_ref(feature), key]
      end

    Runtime.call(cid, "removeFeatureState", args)
  end

  defp camera_options(opts) do
    props = Enum.into(opts, %{})

    props
    |> Map.put(:center, Spec.lng_lat(Map.get(props, :center)))
    |> Spec.take(@camera_keys)
  end

  defp feature_ref(feature) do
    feature
    |> Enum.into(%{})
    |> Spec.take(source: "source", id: "id", source_layer: "sourceLayer")
  end

  defp property_name(property) when is_binary(property), do: property

  defp property_name(property) when is_atom(property) do
    property |> Atom.to_string() |> String.replace("_", "-")
  end
end
