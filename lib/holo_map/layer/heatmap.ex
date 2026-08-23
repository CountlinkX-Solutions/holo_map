defmodule HoloMap.Layer.Heatmap do
  @moduledoc """
  Point density rendered as a heat surface.

  A `HoloMap.Layer` locked to `type: "heatmap"`. See that module for the full
  prop list, ordering rules and event payloads — everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `heatmap_color`, `heatmap_intensity`, `heatmap_opacity`, `heatmap_radius`, `heatmap_weight`.

  ## Layout properties

  `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#heatmap).
  """

  use HoloMap.Layer.Base, type: "heatmap"
end
