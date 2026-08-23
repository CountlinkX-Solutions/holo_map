defmodule HoloMap.Layer.Fill do
  @moduledoc """
  Filled polygons.

  A `HoloMap.Layer` locked to `type: "fill"`. See that module for the full
  prop list, ordering rules and event payloads — everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `fill_color`, `fill_opacity`, `fill_outline_color`, `fill_pattern`, `fill_antialias`, `fill_translate`, `fill_translate_anchor`, `fill_sort_key`.

  ## Layout properties

  `fill_sort_key`, `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#fill).
  """

  use HoloMap.Layer.Base, type: "fill"
end
