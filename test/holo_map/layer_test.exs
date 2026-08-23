defmodule HoloMap.LayerTest do
  use HoloMap.RenderCase, async: true

  alias HoloMap.Layer

  doctest HoloMap.Layer.Base

  describe "specification" do
    test "builds a MapLibre layer object" do
      html =
        render_def(HoloMap.Layer.Fill,
          id: "parcels-fill",
          source: "parcels",
          paint: %{fill_color: "#3b82f6", fill_opacity: 0.4}
        )

      assert spec_for(html, "parcels-fill") == %{
               "type" => "fill",
               "source" => "parcels",
               "paint" => %{"fill-color" => "#3b82f6", "fill-opacity" => 0.4}
             }
    end

    test "dasherizes paint and layout, and keeps string keys verbatim" do
      html =
        render_def(HoloMap.Layer.Line,
          id: "roads",
          source: "basemap",
          paint: %{line_width: 2},
          layout: %{"line-cap" => "round", :line_join => "bevel"}
        )

      spec = spec_for(html, "roads")

      assert spec["paint"] == %{"line-width" => 2}
      assert spec["layout"] == %{"line-cap" => "round", "line-join" => "bevel"}
    end

    test "keeps expressions intact" do
      expression = ["interpolate", ["linear"], ["zoom"], 8, 1, 16, 6]

      html =
        render_def(HoloMap.Layer.Line, id: "roads", source: "s", paint: %{line_width: expression})

      assert spec_for(html, "roads")["paint"]["line-width"] == expression
    end

    test "omits empty paint and layout so MapLibre defaults survive" do
      spec = spec_for(render_def(HoloMap.Layer.Fill, id: "l", source: "s"), "l")

      refute Map.has_key?(spec, "paint")
      refute Map.has_key?(spec, "layout")
    end

    test "maps zoom range and source layer onto specification keys" do
      html =
        render_def(HoloMap.Layer.Fill,
          id: "water",
          source: "basemap",
          source_layer: "water",
          min_zoom: 4,
          max_zoom: 14
        )

      spec = spec_for(html, "water")

      assert spec["source-layer"] == "water"
      assert spec["minzoom"] == 4
      assert spec["maxzoom"] == 14
    end

    test "carries before_id for the reconciler to strip" do
      # `beforeId` is not part of the MapLibre layer object — it is the second
      # argument to addLayer — so it travels in the spec and is destructured out.
      html = render_def(HoloMap.Layer.Fill, id: "l", source: "s", before_id: "labels")

      assert spec_for(html, "l")["beforeId"] == "labels"
    end

    test "carries a filter expression" do
      filter = ["==", ["get", "zone"], "R1"]
      html = render_def(HoloMap.Layer.Fill, id: "l", source: "s", filter: filter)

      assert spec_for(html, "l")["filter"] == filter
    end
  end

  describe "visible prop" do
    test "folds into layout.visibility" do
      html = render_def(HoloMap.Layer.Fill, id: "l", source: "s", visible: false)

      assert spec_for(html, "l")["layout"] == %{"visibility" => "none"}
    end

    test "merges with an existing layout map" do
      html =
        render_def(HoloMap.Layer.Line,
          id: "l",
          source: "s",
          layout: %{line_cap: "round"},
          visible: true
        )

      assert spec_for(html, "l")["layout"] == %{"line-cap" => "round", "visibility" => "visible"}
    end

    test "leaves a hand-written visibility alone when unset" do
      html = render_def(HoloMap.Layer.Fill, id: "l", source: "s", layout: %{visibility: "none"})

      assert spec_for(html, "l")["layout"] == %{"visibility" => "none"}
    end
  end

  describe "type" do
    test "each sugar component locks its own layer type" do
      pairs = [
        {HoloMap.Layer.Fill, "fill"},
        {HoloMap.Layer.Line, "line"},
        {HoloMap.Layer.Circle, "circle"},
        {HoloMap.Layer.Symbol, "symbol"},
        {HoloMap.Layer.Raster, "raster"},
        {HoloMap.Layer.Heatmap, "heatmap"},
        {HoloMap.Layer.Hillshade, "hillshade"},
        {HoloMap.Layer.FillExtrusion, "fill-extrusion"}
      ]

      for {module, type} <- pairs do
        html = render_def(module, id: "l", source: "s")
        assert spec_for(html, "l")["type"] == type, "#{inspect(module)} should be #{type}"
      end
    end

    test "the generic layer takes its type from the caller" do
      html = render_def(HoloMap.Layer, id: "l", type: "fill", source: "s")

      assert spec_for(html, "l")["type"] == "fill"
    end

    test "a sugar component has no type prop to override" do
      # The type is a literal in the generated template rather than a prop with
      # a `values:` constraint, because Hologram only checks such constraints
      # while rendering. Here there is nothing to check: a `type` attribute is
      # not a declared prop, so it is filtered out and the layer stays a fill.
      refute Enum.any?(Layer.Fill.__props__(), fn {name, _, _} -> name == :type end)

      html = render_def(HoloMap.Layer.Fill, id: "l", source: "s", type: "line")
      assert spec_for(html, "l")["type"] == "fill"
    end
  end

  describe "events" do
    test "encodes the layer event surface" do
      html =
        render_def(HoloMap.Layer.Fill,
          id: "l",
          source: "s",
          on_click: :picked,
          on_mouse_enter: :hovered,
          on_mouse_leave: :unhovered
        )

      events = events_for(html, "l")

      assert Map.keys(events) |> Enum.sort() == ["click", "mouseenter", "mouseleave"]
      assert events["click"]["action"] == "picked"
    end
  end

  test "requires a surrounding map, and says so" do
    # Without the guard, Hologram surfaces this as `KeyError: key :map_cid not
    # found` — an internal prop name that tells the caller nothing.
    assert_raise ArgumentError, ~r/rendered outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Layer.Fill, id: "l", source: "s")
    end
  end
end
