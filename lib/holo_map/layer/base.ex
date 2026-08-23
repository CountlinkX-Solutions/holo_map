defmodule HoloMap.Layer.Base do
  @moduledoc """
  The shared body of every layer component.

  MapLibre's eight layer types differ only in which paint and layout
  properties they accept — the specification shape, the update rules and the
  event surface are identical. Rather than repeat that eight times, each layer
  component is one `use` away from the whole thing:

      defmodule HoloMap.Layer.Fill do
        use HoloMap.Layer.Base, type: "fill"
      end

  Passing no `:type` produces `HoloMap.Layer`, where the caller supplies it.

  ## How the type is fixed

  A type-specific component does not declare a `type` prop at all — the literal
  is baked into its template when the macro expands. That is deliberate: a
  `values: ["fill"]` constraint would only be checked while rendering, and this
  way there is nothing to check, because there is no way to pass a type in.

  ## What the injected component does

  It renders one definition element whose `data-hm-spec` is a MapLibre layer
  object. When a prop changes, the reconciler picks the narrowest update
  available: `setPaintProperty` for a paint change, `setLayoutProperty` for
  layout, `setFilter` for a filter, `setLayerZoomRange` for a zoom range. Only
  a change to `type`, `source` or `source_layer` — none of which MapLibre can
  change in place — forces a remove-and-re-add.
  """

  @spec_keys [
    type: "type",
    source: "source",
    source_layer: "source-layer",
    filter: "filter",
    min_zoom: "minzoom",
    max_zoom: "maxzoom",
    metadata: "metadata",
    before_id: "beforeId"
  ]

  @doc """
  Injects the props, template and specification builder of a layer component.

  ## Options

    * `:type` — the MapLibre layer type this component is locked to. When
      given, the type is a literal in the generated template and there is no
      `type` prop. When omitted, `type` becomes a required prop.
  """
  defmacro __using__(opts) do
    type = Keyword.get(opts, :type)

    type_prop =
      if type do
        quote do: nil
      else
        quote do: prop(:type, :string, required: true)
      end

    # The template is assembled as a string so the layer type can be a literal
    # rather than a prop lookup, then handed to ~HOLO as the binary the sigil
    # would have received anyway.
    type_expression = if type, do: ~s("#{type}"), else: "@type"
    template_ast = {:sigil_HOLO, [], [{:<<>>, [], [template_string(type_expression)]}, []]}

    quote do
      use HoloMap.Def

      prop :id, :string, required: true
      unquote(type_prop)
      prop :source, :string, default: nil
      prop :source_layer, :string, default: nil
      prop :paint, :map, default: %{}
      prop :layout, :map, default: %{}
      prop :filter, :list, default: nil
      prop :min_zoom, :any, default: nil
      prop :max_zoom, :any, default: nil
      prop :before_id, :string, default: nil
      prop :visible, :any, default: nil
      prop :metadata, :map, default: nil

      prop :on_click, :any, default: nil
      prop :on_dbl_click, :any, default: nil
      prop :on_context_menu, :any, default: nil
      prop :on_mouse_enter, :any, default: nil
      prop :on_mouse_leave, :any, default: nil
      prop :on_mouse_move, :any, default: nil
      prop :on_mouse_down, :any, default: nil
      prop :on_mouse_up, :any, default: nil
      prop :on_touch_start, :any, default: nil
      prop :on_touch_end, :any, default: nil

      @impl Hologram.Component
      def template do
        unquote(template_ast)
      end
    end
  end

  @doc false
  def template_string(type_expression) do
    """
    <div
      data-hm="layer"
      data-hm-key={@id}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Layer.Base.build(%{
        type: #{type_expression},
        source: @source,
        source_layer: @source_layer,
        paint: @paint,
        layout: @layout,
        filter: @filter,
        min_zoom: @min_zoom,
        max_zoom: @max_zoom,
        before_id: @before_id,
        visible: @visible,
        metadata: @metadata
      })}
      data-hm-events={HoloMap.Def.events(
        click: @on_click,
        dblclick: @on_dbl_click,
        contextmenu: @on_context_menu,
        mouseenter: @on_mouse_enter,
        mouseleave: @on_mouse_leave,
        mousemove: @on_mouse_move,
        mousedown: @on_mouse_down,
        mouseup: @on_mouse_up,
        touchstart: @on_touch_start,
        touchend: @on_touch_end
      )}
    ></div>
    """
  end

  @doc """
  Builds the JSON layer specification for a definition element.

  Paint and layout maps are dasherized (`fill_color` becomes `"fill-color"`),
  the `visible` prop is folded into `layout.visibility`, and empty paint or
  layout maps are dropped so an untouched layer keeps MapLibre's defaults.

      iex> HoloMap.Layer.Base.build(%{type: "fill", source: "parcels", paint: %{fill_color: "#f00"},
      ...>   layout: %{}, filter: nil, min_zoom: nil, max_zoom: nil, before_id: nil,
      ...>   visible: nil, metadata: nil, source_layer: nil})
      ~s({"paint":{"fill-color":"#f00"},"source":"parcels","type":"fill"})
  """
  @spec build(map()) :: String.t()
  def build(props) do
    layout =
      props.layout
      |> HoloMap.Spec.dasherize()
      |> HoloMap.Def.visibility(HoloMap.Spec.boolean(props.visible))

    paint = HoloMap.Spec.dasherize(props.paint)

    props
    |> HoloMap.Spec.take(@spec_keys)
    |> Map.put("paint", blank_to_nil(paint))
    |> Map.put("layout", blank_to_nil(layout))
    |> HoloMap.Def.spec()
  end

  defp blank_to_nil(map) when map_size(map) == 0, do: nil
  defp blank_to_nil(map), do: map
end
