defmodule HoloMap.Control.Terrain do
  @moduledoc """
  A button that lets the user turn 3D terrain on and off.

      <HoloMap.Source.RasterDEM id="dem" url={@dem_url} encoding="terrarium" />
      <HoloMap.Control.Terrain source="dem" exaggeration={1.5} />

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `position` | string | Corner to place the control in. Default `"top-right"` |
  | `source` | string | **Required.** The `id` of a `HoloMap.Source.RasterDEM` |
  | `exaggeration` | number | Vertical multiplier applied when the user turns terrain on |

  ## This is not `HoloMap.Terrain`

  The two look similar and mean opposite things.

  `HoloMap.Terrain` is a declaration: while the component is rendered, terrain
  is on. Your application decides.

  `HoloMap.Control.Terrain` is a button: it hands the decision to the user, and
  the map starts flat.

  Rendering both puts them in conflict. The declaration wins whenever it is
  re-applied — so a user who switches terrain off with the button will see it
  come back the next time the `HoloMap.Terrain` component's props change. Pick
  one. If you want a toggle *and* control over the initial state, use
  `HoloMap.Terrain` behind a conditional and drive it from your own state:

      {%if @terrain_on}
        <HoloMap.Terrain source="dem" exaggeration={1.5} />
      {/if}

  ## Getting anything to show

  Terrain does nothing at zero pitch. Give the map a `pitch`, raise `max_pitch`,
  and add `HoloMap.Control.Navigation` with `visualize_pitch` so the user can
  tilt back and forth — otherwise the button appears to do nothing at all.
  """

  use HoloMap.Def

  @keys [source: "source", exaggeration: "exaggeration"]

  prop :position, :string,
    default: "top-right",
    values: ["top-left", "top-right", "bottom-left", "bottom-right"]

  prop :source, :string, required: true
  prop :exaggeration, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="control"
      data-hm-key={"control:terrain:" <> @position}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Control.build(
        %{source: @source, exaggeration: @exaggeration},
        HoloMap.Control.Terrain.__keys__(),
        "terrain",
        @position
      )}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
