defmodule HoloMap.Control.Globe do
  @moduledoc """
  A button that switches the map between the flat mercator projection and a globe.

      <HoloMap.Control.Globe position="top-right" />

  New in MapLibre GL JS 6. The projection is a rendering choice, not data: the
  same sources and layers draw either way, and nothing in your components needs
  to know which is active.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `position` | string | Corner to place the control in. Default `"top-right"` |

  The control takes no options of its own, because MapLibre's `GlobeControl`
  constructor accepts none.

  ## When a globe helps

  At low zoom the mercator projection inflates everything far from the equator,
  which is the wrong story for anything global: coverage maps, flight paths,
  climate data. A globe removes that distortion and makes polar regions
  readable. Past roughly zoom 6 the two are indistinguishable, so the control
  earns its place on world views and clutters a city map.

  Pair it with `HoloMap.Control.Navigation`. A rotated globe is much easier to
  reset with a compass than by dragging.
  """

  use HoloMap.Def

  prop :position, :string,
    default: "top-right",
    values: ["top-left", "top-right", "bottom-left", "bottom-right"]

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="control"
      data-hm-key={"control:globe:" <> @position}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Control.build(%{}, [], "globe", @position)}
    ></div>
    """
  end
end
