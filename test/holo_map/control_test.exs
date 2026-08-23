defmodule HoloMap.ControlTest do
  use HoloMap.RenderCase, async: true

  test "navigation carries its toggles" do
    html =
      render_def(HoloMap.Control.Navigation,
        position: "top-left",
        show_compass: false,
        visualize_pitch: true
      )

    assert spec_for(html, "control:navigation:top-left") == %{
             "control" => "navigation",
             "position" => "top-left",
             "showCompass" => false,
             "visualizePitch" => true
           }
  end

  test "controls default to the top-right corner" do
    html = render_def(HoloMap.Control.Fullscreen, [])

    assert spec_for(html, "control:fullscreen:top-right") == %{
             "control" => "fullscreen",
             "position" => "top-right"
           }
  end

  test "the key includes the position, so moving a control replaces it" do
    # MapLibre cannot move a control between corners, so position is part of
    # identity: a change there has to become a remove plus an add.
    html = render_def(HoloMap.Control.Scale, position: "bottom-left", unit: "metric")

    assert spec_for(html, "control:scale:bottom-left")["unit"] == "metric"
    assert spec_for(html, "control:scale:top-right") == nil
  end

  test "geolocate maps its nested option maps" do
    html =
      render_def(HoloMap.Control.Geolocate,
        track_user_location: true,
        show_user_heading: true,
        position_options: %{"enableHighAccuracy" => true},
        fit_bounds_options: %{"maxZoom" => 16}
      )

    spec = spec_for(html, "control:geolocate:top-right")

    assert spec["trackUserLocation"] == true
    assert spec["showUserHeading"] == true
    assert spec["positionOptions"] == %{"enableHighAccuracy" => true}
    assert spec["fitBoundsOptions"] == %{"maxZoom" => 16}
  end

  test "attribution carries compact and custom credits" do
    html =
      render_def(HoloMap.Control.Attribution,
        compact: true,
        custom_attribution: "© Example"
      )

    spec = spec_for(html, "control:attribution:top-right")

    assert spec["compact"] == true
    assert spec["customAttribution"] == "© Example"
  end

  test "an invalid position is rejected by name" do
    # MapLibre would otherwise throw from inside addControl, naming neither the
    # control nor the prop that was wrong.
    assert_raise ArgumentError, ~r/invalid position "middle" for the navigation control/, fn ->
      render_def(HoloMap.Control.Navigation, position: "middle")
    end
  end

  test "controls require a surrounding map" do
    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Control.Navigation, [])
    end
  end
end

defmodule HoloMap.NewControlTest do
  use HoloMap.RenderCase, async: true

  describe "Globe" do
    test "carries no options beyond its position" do
      html = render_def(HoloMap.Control.Globe, position: "bottom-left")

      assert spec_for(html, "control:globe:bottom-left") == %{
               "control" => "globe",
               "position" => "bottom-left"
             }
    end

    test "defaults to the top-right corner" do
      html = render_def(HoloMap.Control.Globe, [])

      assert spec_for(html, "control:globe:top-right")["control"] == "globe"
    end
  end

  describe "Terrain" do
    test "carries the DEM source and exaggeration" do
      html = render_def(HoloMap.Control.Terrain, source: "dem", exaggeration: 1.5)

      assert spec_for(html, "control:terrain:top-right") == %{
               "control" => "terrain",
               "position" => "top-right",
               "source" => "dem",
               "exaggeration" => 1.5
             }
    end

    test "omits exaggeration when unset" do
      spec =
        spec_for(render_def(HoloMap.Control.Terrain, source: "dem"), "control:terrain:top-right")

      refute Map.has_key?(spec, "exaggeration")
    end

    test "requires a source, since MapLibre's constructor does" do
      # A missing `required:` prop surfaces as a KeyError from the template's
      # variable lookup, not as Hologram.PropError. Hologram catches it at
      # compile time for a literal call site in a template; reached any other
      # way — a spread, a dynamic tag, a programmatic render like this one —
      # this is the shape the failure takes.
      assert_raise KeyError, ~r/key :source not found/, fn ->
        render_def(HoloMap.Control.Terrain, [])
      end
    end
  end

  test "both reject an invalid position by name" do
    assert_raise ArgumentError, ~r/invalid position "middle" for the globe control/, fn ->
      render_def(HoloMap.Control.Globe, position: "middle")
    end

    assert_raise ArgumentError, ~r/invalid position "middle" for the terrain control/, fn ->
      render_def(HoloMap.Control.Terrain, source: "dem", position: "middle")
    end
  end

  test "both require a surrounding map" do
    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Control.Globe, [])
    end

    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Control.Terrain, source: "dem")
    end
  end
end
