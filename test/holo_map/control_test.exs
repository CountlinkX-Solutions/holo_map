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
