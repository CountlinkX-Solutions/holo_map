defmodule HoloMap.Control.Fullscreen do
  @moduledoc """
  A button that expands the map to fill the screen.

      <HoloMap.Control.Fullscreen position="top-left" />

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `position` | string | Corner to place the control in. Default `"top-right"` |

  The button expands the map's own container, so anything rendered outside it,
  such as a sidebar or a legend in your own markup, is not part of the
  fullscreen view.
  Put controls that should survive fullscreen inside the map as `HoloMap.Control`
  components.
  """

  use HoloMap.Def

  @keys []

  prop :position, :string,
    default: "top-right",
    values: ["top-left", "top-right", "bottom-left", "bottom-right"]

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="control"
      data-hm-key={"control:fullscreen:" <> @position}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Control.build(%{}, HoloMap.Control.Fullscreen.__keys__(), "fullscreen", @position)}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
