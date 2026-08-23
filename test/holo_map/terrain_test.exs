defmodule HoloMap.TerrainTest do
  use HoloMap.RenderCase, async: true

  describe "Terrain" do
    test "carries the DEM source and exaggeration" do
      html = render_def(HoloMap.Terrain, source: "dem", exaggeration: 1.4)

      assert spec_for(html, "terrain") == %{"source" => "dem", "exaggeration" => 1.4}
    end

    test "omits exaggeration when unset, leaving MapLibre's default" do
      assert spec_for(render_def(HoloMap.Terrain, source: "dem"), "terrain") == %{
               "source" => "dem"
             }
    end
  end

  describe "Sky" do
    test "dasherizes its properties" do
      html =
        render_def(HoloMap.Sky,
          sky_color: "#199EF3",
          horizon_color: "#ffffff",
          fog_ground_blend: 0.5
        )

      assert spec_for(html, "sky") == %{
               "sky-color" => "#199EF3",
               "horizon-color" => "#ffffff",
               "fog-ground-blend" => 0.5
             }
    end

    test "accepts expressions as values" do
      expression = ["interpolate", ["linear"], ["zoom"], 0, 1, 12, 0]
      html = render_def(HoloMap.Sky, atmosphere_blend: expression)

      assert spec_for(html, "sky")["atmosphere-blend"] == expression
    end

    test "merges the extra properties map last" do
      html = render_def(HoloMap.Sky, sky_color: "#000", properties: %{sky_color: "#fff"})

      assert spec_for(html, "sky")["sky-color"] == "#fff"
    end
  end

  test "both require a surrounding map" do
    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Terrain, source: "dem")
    end

    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Sky, sky_color: "#000")
    end
  end
end
