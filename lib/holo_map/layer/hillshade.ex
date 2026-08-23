defmodule HoloMap.Layer.Hillshade do
  @moduledoc """
  Shaded relief, from a `HoloMap.Source.RasterDEM`.

  A `HoloMap.Layer` locked to `type: "hillshade"`. See that module for the full
  prop list, ordering rules and event payloads — everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `hillshade_accent_color`, `hillshade_exaggeration`, `hillshade_highlight_color`, `hillshade_illumination_anchor`, `hillshade_illumination_direction`, `hillshade_shadow_color`.

  ## Layout properties

  `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#hillshade).
  """

  use HoloMap.Layer.Base, type: "hillshade"
end
