defmodule HoloMap.Source do
  @moduledoc """
  Namespace for the data sources a map can draw from.

  A source says *where the data comes from*; a layer says *how it looks*. They
  are separate components because the relationship is one-to-many. One source
  routinely feeds a fill, an outline and a label layer, and re-declaring the
  data three times would mean fetching it three times.

      <HoloMap.Source.GeoJSON id="parcels" data={@parcels} />
      <HoloMap.Layer.Fill id="parcels-fill" source="parcels" paint={%{fill_color: "#3b82f6"}} />
      <HoloMap.Layer.Line id="parcels-line" source="parcels" paint={%{line_color: "#1e40af"}} />

  Layers reference a source by its `id`, and may be declared before or after
  it. A layer whose source is not on the map yet waits for it, and is added in
  its declared place as soon as the source is.

  ## Available sources

    * `HoloMap.Source.GeoJSON`: inline features or a URL, with clustering
    * `HoloMap.Source.Vector`: vector tiles
    * `HoloMap.Source.Raster`: raster tiles
    * `HoloMap.Source.RasterDEM`: elevation tiles, for terrain and hillshade
    * `HoloMap.Source.Image`: a single image pinned to four corners

  ## Updating a source

  How a source is updated depends on what changed:

    * A GeoJSON source whose `data` changed is updated in place with
      `setData`. No layer is disturbed and nothing flickers.
    * An image source whose `url` or `coordinates` changed uses `updateImage`.
    * Any other change is structural. MapLibre refuses to remove a source that
      still has layers attached, so the reconciler detaches the layers it owns,
      swaps the source, and puts them back where they were in the stack.

  Frequently-changing data therefore belongs in a GeoJSON source's `data`
  prop, which is the one path with no teardown.
  """

  @doc false
  @spec build(map(), keyword(), String.t(), [atom()]) :: String.t()
  def build(props, keys, type, boolean_props \\ []) do
    props
    |> HoloMap.Spec.booleans(boolean_props)
    |> HoloMap.Spec.take(keys)
    |> Map.put("type", type)
    |> HoloMap.Def.spec()
  end
end
