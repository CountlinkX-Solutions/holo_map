defmodule HoloMap.Layer.Symbol do
  @moduledoc """
  Icons and text labels.

  A `HoloMap.Layer` locked to `type: "symbol"`. See that module for the full
  prop list, ordering rules and event payloads — everything here is identical
  apart from the layer type, which is fixed and cannot be overridden.

  ## Paint properties

  `text_color`, `text_halo_color`, `text_halo_width`, `text_opacity`, `icon_color`, `icon_opacity`, `icon_halo_color`, `icon_halo_width`, `text_translate`, `icon_translate`.

  ## Layout properties

  `text_field`, `text_font`, `text_size`, `text_anchor`, `text_offset`, `text_allow_overlap`, `text_ignore_placement`, `icon_image`, `icon_size`, `icon_anchor`, `icon_allow_overlap`, `symbol_placement`, `symbol_spacing`, `symbol_sort_key`, `visibility`.

  Property names may be written as atoms in Elixir style (`:fill_color`) or as
  MapLibre specification names (`"fill-color"`); both reach MapLibre as the
  latter. The full reference lives in the
  [MapLibre style specification](https://maplibre.org/maplibre-style-spec/layers/#symbol).
  """

  use HoloMap.Layer.Base, type: "symbol"
end
