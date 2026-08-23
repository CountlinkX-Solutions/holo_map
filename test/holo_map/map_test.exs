defmodule HoloMap.MapTest do
  use HoloMap.RenderCase, async: true

  describe "container markup" do
    test "derives both element ids from the cid" do
      html = render(HoloMap.Map, cid: "explorer", style: "https://example.com/style.json")

      assert html =~ ~s(id="hm--explorer")
      assert html =~ ~s(id="hm--explorer--defs")
    end

    test "hides the definitions container" do
      # Definition elements are bookkeeping, not content — they must never be
      # visible, and must not affect layout around the canvas.
      html = render(HoloMap.Map, cid: "explorer", style: "s.json")

      assert html =~ ~s(id="hm--explorer--defs" hidden)
    end

    test "applies an inline size by default, because a zero-height map renders blank" do
      html = render(HoloMap.Map, cid: "explorer", style: "s.json")

      assert html =~ ~s(style="height:400px;width:100%")
    end

    test "omits the inline style entirely when both dimensions are nil" do
      html = render(HoloMap.Map, cid: "explorer", style: "s.json", height: nil, width: nil)

      refute html =~ "style=\"height"
    end

    test "passes the wrapper class through" do
      html = render(HoloMap.Map, cid: "explorer", style: "s.json", class: "rounded shadow")

      assert html =~ ~s(class="rounded shadow")
    end
  end

  describe "map specification" do
    test "carries the constructor options MapLibre needs" do
      html =
        render(HoloMap.Map,
          cid: "explorer",
          style: "https://example.com/style.json",
          center: {-70.66, 19.45},
          zoom: 11,
          bearing: 20,
          pitch: 45
        )

      assert spec_for(html, "map") == %{
               "style" => "https://example.com/style.json",
               "center" => [-70.66, 19.45],
               "zoom" => 11,
               "bearing" => 20,
               "pitch" => 45,
               "workerUrl" => "/assets/maplibre-gl-worker.mjs"
             }
    end

    test "normalises max_bounds from any accepted shape" do
      html =
        render(HoloMap.Map, cid: "m", style: "s.json", max_bounds: [-71.0, 19.0, -70.0, 20.0])

      assert spec_for(html, "map")["maxBounds"] == [[-71.0, 19.0], [-70.0, 20.0]]
    end

    test "maps snake_case props onto MapLibre's camelCase option names" do
      html =
        render(HoloMap.Map,
          cid: "m",
          style: "s.json",
          min_zoom: 4,
          max_zoom: 18,
          attribution_control: false,
          cooperative_gestures: true,
          local_ideograph_font_family: "sans-serif"
        )

      spec = spec_for(html, "map")

      assert spec["minZoom"] == 4
      assert spec["maxZoom"] == 18
      assert spec["attributionControl"] == false
      assert spec["cooperativeGestures"] == true
      assert spec["localIdeographFontFamily"] == "sans-serif"
    end

    test "keeps false rather than dropping it as unset" do
      # `interactive: false` is the whole point of a static map — losing it to
      # nil-stripping would silently produce an interactive one.
      html = render(HoloMap.Map, cid: "m", style: "s.json", interactive: false)

      assert spec_for(html, "map")["interactive"] == false
    end

    test "omits props that were never set" do
      spec = spec_for(render(HoloMap.Map, cid: "m", style: "s.json"), "map")

      # `workerUrl` is the one option with a non-nil default: MapLibre's own
      # resolution of its worker file breaks once the library is bundled, so
      # the path is always sent.
      assert Map.keys(spec) == ["style", "workerUrl"]
    end

    test "the worker url can be pointed elsewhere" do
      html = render(HoloMap.Map, cid: "m", style: "s.json", worker_url: "/static/ml-worker.mjs")

      assert spec_for(html, "map")["workerUrl"] == "/static/ml-worker.mjs"
    end

    test "merges the raw options escape hatch last" do
      html =
        render(HoloMap.Map,
          cid: "m",
          style: "s.json",
          zoom: 5,
          options: %{"maxCanvasSize" => [2048, 2048], "zoom" => 9}
        )

      spec = spec_for(html, "map")

      assert spec["maxCanvasSize"] == [2048, 2048]
      assert spec["zoom"] == 9, "raw options are documented as winning"
    end
  end

  describe "events" do
    test "encodes only the handlers that are set" do
      html =
        render(HoloMap.Map,
          cid: "m",
          style: "s.json",
          on_move_end: :map_moved,
          on_click: %{action: :map_clicked, target: "sidebar"}
        )

      assert events_for(html, "map") == %{
               "moveend" => %{"action" => "map_moved", "target" => "page", "params" => %{}},
               "click" => %{"action" => "map_clicked", "target" => "sidebar", "params" => %{}}
             }
    end

    test "emits an empty object when no handler is set" do
      assert events_for(render(HoloMap.Map, cid: "m", style: "s.json"), "map") == %{}
    end
  end

  describe "lifecycle" do
    test "schedules the boot action on mount" do
      # JS interop is a no-op during SSR and inside init, so the map can only
      # be constructed from an action. Losing this chained action would mean a
      # component that renders a container and never becomes a map.
      {component, _server} =
        HoloMap.Map.init(%{cid: "explorer"}, %Hologram.Component{}, %Hologram.Server{})

      assert component.state.map_cid == "explorer"
      assert %Hologram.Component.Action{name: :__holo_map_boot__} = component.next_action
    end

    test "publishes its cid on the context children read from" do
      {component, _server} =
        HoloMap.Map.init(%{cid: "explorer"}, %Hologram.Component{}, %Hologram.Server{})

      assert component.emitted_context[HoloMap.Def.context_key()] == "explorer"
    end

    test "the client-side init does the same" do
      component = HoloMap.Map.init(%{cid: "explorer"}, %Hologram.Component{})

      assert component.state.map_cid == "explorer"
      assert component.emitted_context[HoloMap.Def.context_key()] == "explorer"
    end
  end
end
