defmodule HoloMap.Layer.Raster do
  @moduledoc """
  Raster tiles, from a `HoloMap.Source.Raster`.

  A `HoloMap.Layer` locked to `type: "raster"`. See that module for the full
  prop list, ordering rules and event payloads. Everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `raster_opacity`, `raster_brightness_min`, `raster_brightness_max`, `raster_contrast`, `raster_saturation`, `raster_hue_rotate`, `raster_resampling`, `raster_fade_duration`.

  ## Layout properties

  `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#raster).
  """

  use HoloMap.Layer.Base, type: "raster"
end
