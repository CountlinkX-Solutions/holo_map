defmodule HoloMap.Source.Image do
  @moduledoc """
  A single image pinned to four geographic corners.

      <HoloMap.Source.Image
        id="floorplan"
        url="/images/floor-3.png"
        coordinates={[
          {-70.6620, 19.4530},
          {-70.6600, 19.4530},
          {-70.6600, 19.4515},
          {-70.6620, 19.4515}
        ]}
      />
      <HoloMap.Layer.Raster id="floorplan-layer" source="floorplan" />

  Corners are listed clockwise from the **top left**: top-left, top-right,
  bottom-right, bottom-left. They are corners of the image, not a bounding box,
  so the image can be placed rotated or skewed.

  Useful for floor plans, historical map scans, weather frames and site
  overlays. Anything that is one picture rather than a tile pyramid.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** Referenced by layers' `source` prop |
  | `url` | string | **Required.** Image URL |
  | `coordinates` | list | **Required.** Four `{lng, lat}` corners, clockwise from top-left |

  Changing `url` or `coordinates` uses MapLibre's `updateImage`, so an animated
  sequence, such as a radar loop or a time series, swaps frames without rebuilding the
  source or disturbing the layer above it.
  """

  use HoloMap.Def

  prop :id, :string, required: true
  prop :url, :string, required: true
  prop :coordinates, :list, required: true

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="source"
      data-hm-key={@id}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Source.Image.build(@url, @coordinates)}
    ></div>
    """
  end

  @doc false
  @spec build(String.t(), list()) :: String.t()
  def build(url, coordinates) do
    HoloMap.Def.spec(%{
      "type" => "image",
      "url" => url,
      "coordinates" => Enum.map(coordinates, &HoloMap.Spec.lng_lat/1)
    })
  end
end
