defmodule HoloMap.OverlayTest do
  use HoloMap.RenderCase, async: true

  describe "Marker" do
    test "normalises the coordinate and carries pin options" do
      html =
        render_def(HoloMap.Marker,
          id: "office",
          lng_lat: {-70.66, 19.45},
          color: "#ef4444",
          scale: 1.2,
          draggable: true
        )

      assert spec_for(html, "office") == %{
               "lngLat" => [-70.66, 19.45],
               "color" => "#ef4444",
               "scale" => 1.2,
               "draggable" => true
             }
    end

    test "maps alignment props onto camelCase" do
      html =
        render_def(HoloMap.Marker,
          id: "m",
          lng_lat: {0, 0},
          pitch_alignment: "map",
          rotation_alignment: "viewport",
          class_name: "pin"
        )

      spec = spec_for(html, "m")

      assert spec["pitchAlignment"] == "map"
      assert spec["rotationAlignment"] == "viewport"
      assert spec["className"] == "pin"
    end

    test "nests popup html and options under a single key" do
      # Passed as an expression, which is the only way raw HTML survives:
      # Hologram escapes literal text attributes before a component sees them.
      html =
        render_def(HoloMap.Marker,
          id: "m",
          lng_lat: {0, 0},
          popup_html: {:expr, "<b>Head office</b>"},
          popup_options: %{"offset" => 24}
        )

      assert spec_for(html, "m")["popup"] == %{
               "html" => "<b>Head office</b>",
               "options" => %{"offset" => 24}
             }
    end

    test "omits the popup key entirely when no html is given" do
      refute Map.has_key?(
               spec_for(render_def(HoloMap.Marker, id: "m", lng_lat: {0, 0}), "m"),
               "popup"
             )
    end

    test "renders a content holder for slot markup" do
      # The reconciler decides between MapLibre's default pin and a custom
      # element by whether this holder has content, so it must always exist.
      html = render_def(HoloMap.Marker, id: "m", lng_lat: {0, 0})

      assert html =~ "data-hm-content"
    end

    test "encodes drag and click handlers" do
      html =
        render_def(HoloMap.Marker,
          id: "m",
          lng_lat: {0, 0},
          on_click: :picked,
          on_drag_end: :moved
        )

      events = events_for(html, "m")

      assert events["click"]["action"] == "picked"
      assert events["dragend"]["action"] == "moved"
    end
  end

  describe "Popup" do
    test "normalises the coordinate and carries options" do
      html =
        render_def(HoloMap.Popup,
          id: "details",
          lng_lat: {-70.66, 19.45},
          close_button: false,
          close_on_click: true,
          max_width: "320px"
        )

      assert spec_for(html, "details") == %{
               "lngLat" => [-70.66, 19.45],
               "closeButton" => false,
               "closeOnClick" => true,
               "maxWidth" => "320px"
             }
    end

    test "accepts html instead of slot content" do
      html = render_def(HoloMap.Popup, id: "p", lng_lat: {0, 0}, html: {:expr, "<b>hi</b>"})

      assert spec_for(html, "p")["html"] == "<b>hi</b>"
    end

    test "a literal HTML attribute is escaped, as Hologram escapes all text attributes" do
      # Documented in HoloMap.Popup: raw markup has to arrive through an
      # expression. Pinned here so the caveat cannot drift from the behaviour.
      html = render_def(HoloMap.Popup, id: "p", lng_lat: {0, 0}, html: "<b>hi</b>")

      assert spec_for(html, "p")["html"] == "&lt;b&gt;hi&lt;/b&gt;"
    end
  end

  test "overlays require a surrounding map" do
    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Marker, id: "m", lng_lat: {0, 0})
    end

    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Popup, id: "p", lng_lat: {0, 0})
    end
  end
end
