defmodule HoloMap.Layer.Line do
  @moduledoc """
  Stroked lines.

  A `HoloMap.Layer` locked to `type: "line"`. See that module for the full
  prop list, ordering rules and event payloads — everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `line_color`, `line_width`, `line_opacity`, `line_blur`, `line_dasharray`, `line_gap_width`, `line_offset`, `line_pattern`, `line_gradient`, `line_translate`.

  ## Layout properties

  `line_cap`, `line_join`, `line_miter_limit`, `line_round_limit`, `line_sort_key`, `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#line).
  """

  use HoloMap.Layer.Base, type: "line"
end
