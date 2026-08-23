defmodule HoloMap.BareAttributeTest do
  use HoloMap.RenderCase, async: true

  # A bare attribute in a HOLO template is an empty string, not `true`. Passing
  # that straight through fails MapLibre's style validation with
  # "boolean expected, string found" — a message that names neither the
  # component nor the prop. Every boolean prop is coerced instead.

  test "a bare boolean attribute on a source means true" do
    html =
      render_def(HoloMap.Source.GeoJSON, id: "s", data: "/s.json", cluster: "", generate_id: "")

    spec = spec_for(html, "s")

    assert spec["cluster"] == true
    assert spec["generateId"] == true
  end

  test "a bare boolean attribute on the map means true" do
    html = render(HoloMap.Map, cid: "m", style: "s.json", cooperative_gestures: "", hash: "")

    spec = spec_for(html, "map")

    assert spec["cooperativeGestures"] == true
    assert spec["hash"] == true
  end

  test "a bare boolean attribute on a marker, popup and control means true" do
    marker = render_def(HoloMap.Marker, id: "m", lng_lat: {0, 0}, draggable: "")
    assert spec_for(marker, "m")["draggable"] == true

    popup = render_def(HoloMap.Popup, id: "p", lng_lat: {0, 0}, close_button: "")
    assert spec_for(popup, "p")["closeButton"] == true

    control = render_def(HoloMap.Control.Navigation, visualize_pitch: "")
    assert spec_for(control, "control:navigation:top-right")["visualizePitch"] == true
  end

  test "a bare visible attribute on a layer means visible" do
    html = render_def(HoloMap.Layer.Fill, id: "l", source: "s", visible: "")

    assert spec_for(html, "l")["layout"] == %{"visibility" => "visible"}
  end

  test "an explicit false still means false" do
    html = render(HoloMap.Map, cid: "m", style: "s.json", interactive: false)

    assert spec_for(html, "map")["interactive"] == false
  end

  test "a non-boolean value is rejected rather than coerced" do
    assert_raise ArgumentError, ~r/expected a boolean/, fn ->
      render_def(HoloMap.Source.GeoJSON, id: "s", data: "/s.json", cluster: "yes")
    end
  end

  test "an empty string on a text prop is left alone" do
    # Coercion is opt-in per prop precisely so this stays a string.
    html = render_def(HoloMap.Source.Vector, id: "s", url: "/s.json", attribution: "")

    assert spec_for(html, "s")["attribution"] == ""
  end
end
