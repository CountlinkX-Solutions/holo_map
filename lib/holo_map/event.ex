defmodule HoloMap.Event do
  @moduledoc """
  Normalises the event-handler props that components accept.

  MapLibre events reach Elixir through JavaScript's `Hologram.dispatchAction()`, which needs
  three things: an action name, a target component id, and a params map. Event
  props therefore accept the same shapes Hologram's own longhand event bindings
  do, so there is one syntax to remember:

      # Bare action name — dispatched to the page.
      on_click={:parcel_clicked}

      # Longhand, when the handler lives on a component rather than the page.
      on_click={%{action: :parcel_clicked, target: "sidebar"}}

      # With static params merged into the payload.
      on_click={%{action: :parcel_clicked, target: "sidebar", params: %{layer: "parcels"}}}

  A keyword list works wherever a map does.

  ## Why the default target is the page

  Hologram defaults an event binding to the closest enclosing *stateful*
  component. `HoloMap`'s children are deliberately stateless — they have no
  `cid` of their own — so there is no such component to fall back on, and
  silently targeting the map container would send the action to `HoloMap.Map`
  rather than to the caller's handler. `"page"` is both the common case and the
  one target that always exists.

  ## Event payload

  Whatever `params` you supply is merged *under* the runtime payload, so the
  data MapLibre reports always wins over a static value with the same key. The
  payload keys a handler can expect are documented per component, and the full
  list is in the [Events guide](events.html).
  """

  @typedoc "Any accepted event-handler prop value."
  @type handler :: atom() | map() | keyword() | nil

  @doc """
  Normalises a handler prop into the map the browser reconciler consumes.

  Returns `nil` for an unset handler, which is how a component signals that no
  MapLibre listener should be attached at all.

      iex> HoloMap.Event.normalize(:parcel_clicked)
      %{"action" => "parcel_clicked", "target" => "page", "params" => %{}}

      iex> HoloMap.Event.normalize(%{action: :zoomed, target: "sidebar"})
      %{"action" => "zoomed", "target" => "sidebar", "params" => %{}}

      iex> HoloMap.Event.normalize(%{action: :picked, params: %{layer: "parcels"}})
      %{"action" => "picked", "target" => "page", "params" => %{"layer" => "parcels"}}

      iex> HoloMap.Event.normalize(nil)
      nil
  """
  @spec normalize(handler()) :: map() | nil
  def normalize(nil), do: nil

  def normalize(action) when is_atom(action) do
    build(action, "page", %{})
  end

  def normalize(spec) when is_list(spec) do
    spec |> Enum.into(%{}) |> normalize()
  end

  def normalize(%{} = spec) do
    action = Map.get(spec, :action) || Map.get(spec, "action")

    if is_nil(action) do
      raise ArgumentError,
            "an event handler map must have an :action key, got: #{inspect(spec)}"
    end

    target = Map.get(spec, :target) || Map.get(spec, "target") || "page"
    params = Map.get(spec, :params) || Map.get(spec, "params") || %{}

    build(action, target, params)
  end

  def normalize(other) do
    raise ArgumentError,
          "expected an action name atom, or a map/keyword list with an :action key, " <>
            "got: #{inspect(other)}"
  end

  defp build(action, target, params) when is_atom(action) do
    build(Atom.to_string(action), target, params)
  end

  defp build(action, target, params) when is_binary(action) and is_binary(target) do
    %{"action" => action, "target" => target, "params" => stringify_keys(params)}
  end

  defp build(action, target, _params) do
    raise ArgumentError,
          "an event handler needs an action name and a target cid string, " <>
            "got action: #{inspect(action)}, target: #{inspect(target)}"
  end

  # Action params cross into JavaScript and come back as an action's `params`
  # map, where Hologram turns object keys into atoms. Normalising to strings
  # here means an atom key and a string key can never produce two entries that
  # collapse into one on the way back.
  defp stringify_keys(params) when is_map(params) do
    Enum.into(params, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} when is_binary(key) -> {key, value}
    end)
  end

  defp stringify_keys(params) when is_list(params) do
    params |> Enum.into(%{}) |> stringify_keys()
  end
end
