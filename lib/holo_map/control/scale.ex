defmodule HoloMap.Control.Scale do
  @moduledoc """
  A scale bar showing ground distance.

      <HoloMap.Control.Scale unit="metric" max_width={120} position="bottom-left" />

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `position` | string | Corner to place the control in. Default `"top-right"` |
  | `unit` | string | `"metric"`, `"imperial"` or `"nautical"` |
  | `max_width` | number | Maximum bar width in pixels. Default 100 |

  The bar picks a round distance that fits within `max_width`, so the number
  changes as the user zooms.
  """

  use HoloMap.Def

  @keys [unit: "unit", max_width: "maxWidth"]

  prop :position, :string,
    default: "top-right",
    values: ["top-left", "top-right", "bottom-left", "bottom-right"]

  prop :unit, :string, default: nil, values: [nil, "metric", "imperial", "nautical"]
  prop :max_width, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="control"
      data-hm-key={"control:scale:" <> @position}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Control.build(%{unit: @unit, max_width: @max_width}, HoloMap.Control.Scale.__keys__(), "scale", @position)}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
