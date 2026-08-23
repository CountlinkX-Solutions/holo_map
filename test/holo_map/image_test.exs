defmodule HoloMap.ImageTest do
  use HoloMap.RenderCase, async: true

  test "carries the url" do
    html = render_def(HoloMap.Image, id: "pin", url: "/icons/pin.png")

    assert spec_for(html, "pin") == %{"url" => "/icons/pin.png"}
  end

  test "maps metadata onto MapLibre's camelCase names" do
    html =
      render_def(HoloMap.Image,
        id: "pin",
        url: "/icons/pin.png",
        pixel_ratio: 2,
        stretch_x: [[25, 55]],
        stretch_y: [[25, 55]],
        content: [25, 25, 115, 100]
      )

    spec = spec_for(html, "pin")

    assert spec["pixelRatio"] == 2
    assert spec["stretchX"] == [[25, 55]]
    assert spec["stretchY"] == [[25, 55]]
    assert spec["content"] == [25, 25, 115, 100]
  end

  test "sdf is coerced from a bare attribute" do
    assert spec_for(render_def(HoloMap.Image, id: "pin", url: "/p.png", sdf: ""), "pin")["sdf"] ==
             true

    assert spec_for(render_def(HoloMap.Image, id: "pin", url: "/p.png", sdf: false), "pin")["sdf"] ==
             false
  end

  test "omits metadata that was never set" do
    spec = spec_for(render_def(HoloMap.Image, id: "pin", url: "/p.png"), "pin")

    assert Map.keys(spec) == ["url"]
  end

  test "the definition key is the name layers will use" do
    html = render_def(HoloMap.Image, id: "brand-pin", url: "/p.png")

    assert html =~ ~s(data-hm="image")
    assert html =~ ~s(data-hm-key="brand-pin")
  end

  test "requires an id and a url" do
    assert_raise KeyError, ~r/key :url not found/, fn ->
      render_def(HoloMap.Image, id: "pin")
    end
  end

  test "requires a surrounding map" do
    assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn ->
      render(HoloMap.Image, id: "pin", url: "/p.png")
    end
  end
end
