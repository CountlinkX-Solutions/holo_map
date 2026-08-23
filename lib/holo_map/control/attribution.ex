defmodule HoloMap.Control.Attribution do
  @moduledoc """
  Data attribution for the sources on the map.

      <HoloMap.Map cid="explorer" style={@style} attribution_control={false}>
        <HoloMap.Control.Attribution compact position="bottom-right" />
      </HoloMap.Map>

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `position` | string | Corner to place the control in. Default `"top-right"` |
  | `compact` | boolean | Collapse to an ⓘ button that expands on click |
  | `custom_attribution` | string or list | Extra credits, alongside the ones sources declare |

  Set `attribution_control={false}` on `HoloMap.Map` when using this component,
  or the map ends up with two attribution controls, because MapLibre adds one by
  default.
  """

  use HoloMap.Def

  @keys [compact: "compact", custom_attribution: "customAttribution"]

  prop :position, :string,
    default: "top-right",
    values: ["top-left", "top-right", "bottom-left", "bottom-right"]

  prop :compact, :any, default: nil
  prop :custom_attribution, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="control"
      data-hm-key={"control:attribution:" <> @position}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Control.build(%{compact: @compact, custom_attribution: @custom_attribution}, HoloMap.Control.Attribution.__keys__(), "attribution", @position, [:compact])}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
