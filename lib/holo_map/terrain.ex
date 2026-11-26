defmodule HoloMap.Terrain do
  @moduledoc """
  3D terrain, draped over the map from an elevation source.

      <HoloMap.Source.RasterDEM id="dem" tiles={@dem_tiles} encoding="terrarium" />
      <HoloMap.Terrain source="dem" exaggeration={1.4} />

  Terrain is a property of the map, not a layer. There is one, or there is
  none. Declaring the component turns it on; removing it from the template
  turns it off and the map flattens back out.

  Like a layer, terrain waits for its source: declared above the
  `HoloMap.Source.RasterDEM` it names, or while that source is not rendered, it
  turns on once the source is. Removing the source turns terrain off, with a
  console warning, until the source is rendered again.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `source` | string | **Required.** The `id` of a `HoloMap.Source.RasterDEM` |
  | `exaggeration` | number | Vertical multiplier. `1.0` is true scale |

  ## Making terrain visible

  Terrain does nothing at zero pitch, because a hill viewed from directly above still
  looks flat. Give the map a `pitch`, and usually let the user change it:

      <HoloMap.Map cid="relief" style={@style} pitch={60} max_pitch={85}>
        <HoloMap.Source.RasterDEM id="dem" tiles={@dem_tiles} />
        <HoloMap.Terrain source="dem" exaggeration={1.4} />
        <HoloMap.Control.Navigation visualize_pitch />
      </HoloMap.Map>

  Exaggeration above roughly `2.0` reads as a video-game landscape rather than
  a map, which is a choice worth making deliberately.

  Pair with `HoloMap.Layer.Hillshade` on the same DEM source for shaded relief,
  and `HoloMap.Sky` for an atmosphere at the horizon.
  """

  use HoloMap.Def

  prop :source, :string, required: true
  prop :exaggeration, :any, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="terrain"
      data-hm-key="terrain"
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Def.spec(%{"source" => @source, "exaggeration" => @exaggeration})}
    ></div>
    """
  end
end
