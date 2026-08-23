defmodule HoloMap.SpecTest do
  use ExUnit.Case, async: true

  doctest HoloMap.Spec

  alias HoloMap.Spec

  describe "dasherize/1" do
    test "converts atom keys and keeps string keys" do
      assert Spec.dasherize(%{"line-cap" => "round", :fill_color => "#f00"}) ==
               %{"fill-color" => "#f00", "line-cap" => "round"}
    end

    test "drops nil values rather than emitting null" do
      # MapLibre reads an explicit null as "reset to the default", which is not
      # what an unset prop means.
      assert Spec.dasherize(%{fill_color: nil, fill_opacity: 0}) == %{"fill-opacity" => 0}
    end

    test "leaves expression values untouched" do
      expression = ["interpolate", ["linear"], ["zoom"], 0, 1]
      assert Spec.dasherize(%{line_width: expression}) == %{"line-width" => expression}
    end

    test "raises on a key that is neither atom nor string" do
      assert_raise ArgumentError, ~r/paint\/layout property name/, fn ->
        Spec.dasherize(%{1 => "x"})
      end
    end
  end

  describe "take/2" do
    test "maps props onto their exact specification keys" do
      props = %{source_layer: "water", min_zoom: 4, tile_size: 512}
      table = [source_layer: "source-layer", min_zoom: "minzoom", tile_size: "tileSize"]

      assert Spec.take(props, table) == %{
               "source-layer" => "water",
               "minzoom" => 4,
               "tileSize" => 512
             }
    end

    test "skips absent and nil props" do
      assert Spec.take(%{a: nil}, a: "a", b: "b") == %{}
    end

    test "keeps false, which is a meaningful MapLibre value" do
      assert Spec.take(%{interactive: false}, interactive: "interactive") ==
               %{"interactive" => false}
    end
  end

  describe "merge/1" do
    test "merges left to right and ignores nil fragments" do
      assert Spec.merge([%{"a" => 1}, nil, %{"a" => 2, "b" => 3}]) == %{"a" => 2, "b" => 3}
    end
  end

  describe "lng_lat/1" do
    test "accepts tuples, lists and maps" do
      assert Spec.lng_lat({-70.66, 19.45}) == [-70.66, 19.45]
      assert Spec.lng_lat([-70.66, 19.45]) == [-70.66, 19.45]
      assert Spec.lng_lat(%{lng: -70.66, lat: 19.45}) == [-70.66, 19.45]
    end

    test "passes nil through, so an unset prop stays unset" do
      assert Spec.lng_lat(nil) == nil
    end

    test "raises on anything else" do
      assert_raise ArgumentError, ~r/expected a \{lng, lat\}/, fn -> Spec.lng_lat("here") end
      assert_raise ArgumentError, fn -> Spec.lng_lat([1, 2, 3]) end
    end
  end

  describe "bounds/1" do
    test "accepts a pair of corners" do
      assert Spec.bounds({{-71.0, 19.0}, {-70.0, 20.0}}) == [[-71.0, 19.0], [-70.0, 20.0]]
      assert Spec.bounds([[-71.0, 19.0], [-70.0, 20.0]]) == [[-71.0, 19.0], [-70.0, 20.0]]
    end

    test "accepts the flat GeoJSON bbox shape" do
      assert Spec.bounds([-71.0, 19.0, -70.0, 20.0]) == [[-71.0, 19.0], [-70.0, 20.0]]
    end

    test "passes nil through" do
      assert Spec.bounds(nil) == nil
    end

    test "raises on anything else" do
      assert_raise ArgumentError, ~r/south_west, north_east/, fn -> Spec.bounds([1, 2, 3]) end
    end
  end
end
