defmodule HoloMap.Control do
  @moduledoc """
  Namespace for MapLibre's built-in map controls.

      <HoloMap.Map cid="explorer" style={@style}>
        <HoloMap.Control.Navigation position="top-right" />
        <HoloMap.Control.Scale unit="metric" position="bottom-left" />
      </HoloMap.Map>

  Every control takes a `position`: `"top-left"`, `"top-right"`,
  `"bottom-left"` or `"bottom-right"`, defaulting to `"top-right"`. Several
  controls in the same corner stack in the order they are declared.

  ## Available controls

    * `HoloMap.Control.Navigation`: zoom buttons and a compass
    * `HoloMap.Control.Scale`: a distance scale bar
    * `HoloMap.Control.Geolocate`: locate and follow the user
    * `HoloMap.Control.Fullscreen`: expand the map to fill the screen
    * `HoloMap.Control.Attribution`: data attribution
    * `HoloMap.Control.Globe`: switch between mercator and a globe
    * `HoloMap.Control.Terrain`: let the user toggle 3D terrain

  ## Attribution

  MapLibre adds an attribution control on its own unless told otherwise. Adding
  `HoloMap.Control.Attribution` on top of that produces two. Set
  `attribution_control={false}` on `HoloMap.Map` when you want to place it
  yourself.

  Attribution is usually a licensing obligation rather than a design choice, so
  removing it entirely is generally not yours to decide. Prefer `compact`.

  ## Updates

  Controls carry no updatable state that is worth diffing, so any prop change
  removes and re-adds the control. That is invisible for the built-ins here,
  but it does mean a control is not the place to put a rapidly changing value.
  """

  @positions ~w(top-left top-right bottom-left bottom-right)

  @doc """
  The four corners a control can be placed in.

      iex> HoloMap.Control.positions()
      ["top-left", "top-right", "bottom-left", "bottom-right"]
  """
  @spec positions() :: [String.t()]
  def positions, do: @positions

  @doc false
  @spec build(map(), keyword(), String.t(), String.t(), [atom()]) :: String.t()
  def build(props, keys, control, position, boolean_props \\ []) do
    props
    |> HoloMap.Spec.booleans(boolean_props)
    |> HoloMap.Spec.take(keys)
    |> Map.put("control", control)
    |> Map.put("position", validate_position!(position, control))
    |> HoloMap.Def.spec()
  end

  # A prop's `values:` constraint is only checked while rendering a template,
  # and never for a value that arrives another way. An unchecked position
  # reaches MapLibre's addControl and throws there instead, with a message that
  # names neither the control nor the prop.
  defp validate_position!(position, _control) when position in @positions, do: position

  defp validate_position!(position, control) do
    raise ArgumentError,
          "invalid position #{inspect(position)} for the #{control} control. " <>
            "Expected one of: #{Enum.map_join(@positions, ", ", &inspect/1)}."
  end
end
