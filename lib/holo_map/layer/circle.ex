defmodule HoloMap.Layer.Circle do
  @moduledoc """
  Circles, the usual way to draw points.

  A `HoloMap.Layer` locked to `type: "circle"`. See that module for the full
  prop list, ordering rules and event payloads — everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `circle_color`, `circle_radius`, `circle_opacity`, `circle_blur`, `circle_stroke_color`, `circle_stroke_width`, `circle_stroke_opacity`, `circle_pitch_alignment`, `circle_pitch_scale`, `circle_translate`.

  ## Layout properties

  `circle_sort_key`, `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#circle).
  """

  use HoloMap.Layer.Base, type: "circle"
end
