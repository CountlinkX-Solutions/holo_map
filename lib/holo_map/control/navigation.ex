defmodule HoloMap.Control.Navigation do
  @moduledoc """
  Zoom in/out buttons and a compass.

      <HoloMap.Control.Navigation position="top-right" visualize_pitch />

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `position` | string | Corner to place the control in. Default `"top-right"` |
  | `show_compass` | boolean | Show the compass. Default true |
  | `show_zoom` | boolean | Show the zoom buttons. Default true |
  | `visualize_pitch` | boolean | Tilt the compass needle to reflect pitch |

  The compass is also how a user resets a rotated map. Clicking it returns
  north to up. Hiding it on a map where `drag_rotate` is enabled leaves them
  with no way back.
  """

  use HoloMap.Def

  @keys [show_compass: "showCompass", show_zoom: "showZoom", visualize_pitch: "visualizePitch"]

  prop :position, :string,
    default: "top-right",
    values: ["top-left", "top-right", "bottom-left", "bottom-right"]

  prop :show_compass, :any, default: nil
  prop :show_zoom, :any, default: nil
  prop :visualize_pitch, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="control"
      data-hm-key={"control:navigation:" <> @position}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Control.build(%{show_compass: @show_compass, show_zoom: @show_zoom, visualize_pitch: @visualize_pitch}, HoloMap.Control.Navigation.__keys__(), "navigation", @position, [:show_compass, :show_zoom, :visualize_pitch])}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
