defmodule HoloMap.Layer do
  @moduledoc """
  A MapLibre layer of any type.

      <HoloMap.Layer
        id="parcels-fill"
        type="fill"
        source="parcels"
        paint={%{fill_color: "#3b82f6", fill_opacity: 0.4}}
      />

  Prefer the type-specific components: `HoloMap.Layer.Fill`,
  `HoloMap.Layer.Line`, `HoloMap.Layer.Circle`, `HoloMap.Layer.Symbol`,
  `HoloMap.Layer.Raster`, `HoloMap.Layer.Heatmap`, `HoloMap.Layer.Hillshade`,
  `HoloMap.Layer.FillExtrusion`. They document the paint properties that
  apply to them and reject a mismatched type at compile time. Reach for this
  one when the type is computed at runtime.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** The layer id, and its identity across re-renders |
  | `type` | string | **Required here**, fixed in the type-specific components |
  | `source` | string | The `id` of a source component |
  | `source_layer` | string | Required for vector sources |
  | `paint` | map | Paint properties. Atom keys are dasherized: `fill_color` becomes `"fill-color"` |
  | `layout` | map | Layout properties, dasherized the same way |
  | `filter` | list | A MapLibre filter expression |
  | `min_zoom` / `max_zoom` | number | Zoom range |
  | `before_id` | string | Insert beneath this layer. Ignored while that layer is absent |
  | `visible` | boolean | Convenience for `layout.visibility` |
  | `metadata` | map | Arbitrary data carried on the layer |

  ## Ordering

  Layers stack in the order the components appear in the template. That holds
  for a layer rendered conditionally, one re-added because its `type`, `source`
  or `source_layer` changed, and the layers of a rebuilt source: each goes back
  to its place rather than on top. `before_id` overrides that when a layer has
  to sit beneath one it is not written next to, such as a highlight layer under a
  label layer that belongs to the base style, for example. It can name a layer
  declared further down, or one rendered later, and takes effect once that
  layer is on the map. Changing `before_id` moves the layer.

  ## Events

  `on_click`, `on_dbl_click`, `on_context_menu`, `on_mouse_enter`,
  `on_mouse_leave`, `on_mouse_move`, `on_mouse_down`, `on_mouse_up`,
  `on_touch_start`, `on_touch_end`.

  Handlers receive `layer`, `lng_lat`, `point` and `features`, which holds the features
  under the pointer, each with `id`, `source`, `source_layer`, `properties` and
  `geometry`:

      def action(:parcel_clicked, params, component) do
        case params.features do
          [%{properties: %{parcel_id: id}} | _rest] -> put_state(component, :selected, id)
          [] -> component
        end
      end
  """

  use HoloMap.Layer.Base
end
