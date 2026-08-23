defmodule HoloMap do
  @moduledoc """
  Declarative [MapLibre GL JS](https://maplibre.org/maplibre-gl-js/docs/) map
  components for the [Hologram](https://hologram.page) Elixir framework.

  ## The shape of the library

  A map is written as a component tree. The `HoloMap.Map` container owns the
  MapLibre instance; everything nested inside it declares one piece of the map:

      <HoloMap.Map cid="explorer" style={@style_url} center={{-70.66, 19.45}} zoom={11}>
        <HoloMap.Source.GeoJSON id="parcels" data={@parcels} />
        <HoloMap.Layer.Fill id="parcels-fill" source="parcels" paint={%{fill_color: "#3b82f6"}} />
        <HoloMap.Control.Navigation position="top-right" />
      </HoloMap.Map>

  Children are **stateless** components. They hold no state, run no actions and
  make no JavaScript calls — each one renders a single hidden marker element
  carrying its specification. A reconciler running inside the browser watches
  those elements and translates every addition, removal and attribute change
  into the matching MapLibre call. See `HoloMap.Runtime` and the
  [Architecture guide](architecture.html) for why it works this way.

  The practical consequence: adding a layer, changing a paint property or
  filtering features is an ordinary Hologram state update. You write
  `put_state(component, :fill_color, "#ef4444")` and the map follows.

  ## Component index

  | Group | Components |
  | ----- | ---------- |
  | Container | `HoloMap.Map` |
  | Sources | `HoloMap.Source.GeoJSON`, `HoloMap.Source.Vector`, `HoloMap.Source.Raster`, `HoloMap.Source.RasterDEM`, `HoloMap.Source.Image` |
  | Layers | `HoloMap.Layer` (generic), `HoloMap.Layer.Fill`, `HoloMap.Layer.Line`, `HoloMap.Layer.Circle`, `HoloMap.Layer.Symbol`, `HoloMap.Layer.Raster`, `HoloMap.Layer.Heatmap`, `HoloMap.Layer.Hillshade`, `HoloMap.Layer.FillExtrusion` |
  | Overlays | `HoloMap.Marker`, `HoloMap.Popup` |
  | Controls | `HoloMap.Control.Navigation`, `HoloMap.Control.Scale`, `HoloMap.Control.Geolocate`, `HoloMap.Control.Fullscreen`, `HoloMap.Control.Attribution`, `HoloMap.Control.Globe`, `HoloMap.Control.Terrain` |
  | 3D | `HoloMap.Terrain`, `HoloMap.Sky` |

  For one-off camera moves and property tweaks that don't belong in state, see
  the imperative escape hatch in `HoloMap.API`.

  ## Installation

  `HoloMap` cannot ship its own npm dependency — Hologram resolves bare import
  specifiers against the *host application's* `assets/package.json`. Installing
  `maplibre-gl` and its stylesheet is a step you perform once per application,
  described in the [Installation guide](installation.html).
  """

  @maplibre_version "6.5.0"

  @doc """
  The MapLibre GL JS version this release of `HoloMap` is written against.

      iex> HoloMap.maplibre_version()
      "6.5.0"

  Consumers install their own copy of `maplibre-gl` (see the
  [Installation guide](installation.html)), so this is the version whose
  behaviour the components assume, not a version that is enforced at runtime.
  """
  @spec maplibre_version() :: String.t()
  def maplibre_version, do: @maplibre_version
end
