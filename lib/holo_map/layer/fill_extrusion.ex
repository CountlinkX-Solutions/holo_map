defmodule HoloMap.Layer.FillExtrusion do
  @moduledoc """
  Extruded polygons, the standard way to draw 3D buildings.

  A `HoloMap.Layer` locked to `type: "fill-extrusion"`. See that module for the full
  prop list, ordering rules and event payloads. Everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `fill_extrusion_color`, `fill_extrusion_height`, `fill_extrusion_base`, `fill_extrusion_opacity`, `fill_extrusion_pattern`, `fill_extrusion_translate`, `fill_extrusion_vertical_gradient`.

  ## Layout properties

  `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#fill-extrusion).
  """

  use HoloMap.Layer.Base, type: "fill-extrusion"
end
