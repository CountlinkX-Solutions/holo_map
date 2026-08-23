defmodule HoloMap.JSONTest do
  use ExUnit.Case, async: true

  doctest HoloMap.JSON

  alias HoloMap.JSON

  describe "scalars" do
    test "encodes the JSON primitives" do
      assert JSON.encode(nil) == "null"
      assert JSON.encode(true) == "true"
      assert JSON.encode(false) == "false"
      assert JSON.encode(42) == "42"
      assert JSON.encode(-7) == "-7"
      assert JSON.encode("hi") == ~s("hi")
    end

    test "encodes floats without losing precision" do
      assert JSON.encode(0.5) == "0.5"
      assert JSON.encode(-70.66123) == "-70.66123"
    end

    test "encodes atoms as strings" do
      assert JSON.encode(:visible) == ~s("visible")
    end
  end

  describe "strings" do
    test "escapes what JSON requires" do
      assert JSON.encode(~s(a "b" c)) == ~s("a \\"b\\" c")
      assert JSON.encode("a\\b") == ~s("a\\\\b")
      assert JSON.encode("line\nbreak") == ~s("line\\nbreak")
      assert JSON.encode("tab\there") == ~s("tab\\there")
    end

    test "escapes control characters as \\u00XX" do
      assert JSON.encode(<<0x01>>) == ~s("\\u0001")
      assert JSON.encode(<<0x1F>>) == ~s("\\u001F")
    end

    test "leaves multi-byte UTF-8 intact" do
      # Byte-wise escaping is only safe because continuation bytes are all
      # >= 0x80 and so can never look like an ASCII character needing escape.
      assert JSON.encode("Peña") == ~s("Peña")
      assert JSON.encode("地図") == ~s("地図")
      assert JSON.encode("🗺") == ~s("🗺")
    end
  end

  describe "collections" do
    test "encodes lists, including MapLibre expressions" do
      assert JSON.encode([]) == "[]"
      assert JSON.encode(["get", "name"]) == ~s(["get","name"])

      assert JSON.encode(["interpolate", ["linear"], ["zoom"], 0, 1, 12, 0]) ==
               ~s(["interpolate",["linear"],["zoom"],0,1,12,0])
    end

    test "encodes maps with string, atom and integer keys" do
      assert JSON.encode(%{}) == "{}"
      assert JSON.encode(%{a: 1}) == ~s({"a":1})
      assert JSON.encode(%{"a" => 1}) == ~s({"a":1})
      assert JSON.encode(%{1 => "one"}) == ~s({"1":"one"})
    end

    test "sorts keys so an unchanged spec encodes to an unchanged string" do
      # The reconciler diffs the encoded strings, and Erlang map iteration
      # order is not guaranteed stable — without sorting, an untouched layer
      # could re-encode differently and trigger a spurious MapLibre update.
      assert JSON.encode(%{"z" => 1, "a" => 2, "m" => 3}) == ~s({"a":2,"m":3,"z":1})

      big_one = Enum.into(1..40, %{}, fn i -> {"key#{i}", i} end)
      big_two = 40..1//-1 |> Enum.into(%{}, fn i -> {"key#{i}", i} end)

      assert JSON.encode(big_one) == JSON.encode(big_two)
    end

    test "nests" do
      assert JSON.encode(%{"paint" => %{"fill-color" => ["get", "colour"]}}) ==
               ~s({"paint":{"fill-color":["get","colour"]}})
    end
  end

  describe "rejections" do
    test "raises on terms with no JSON representation" do
      assert_raise ArgumentError, ~r/cannot encode/, fn -> JSON.encode({1, 2}) end
    end

    test "names the struct when one reaches a specification" do
      # Structs are maps and some are Enumerable, so without an explicit clause
      # they either encode a __struct__ field or fail deep inside another one.
      assert_raise ArgumentError, ~r/cannot encode a Date struct/, fn ->
        JSON.encode(%{"date" => ~D[2026-08-22]})
      end

      assert_raise ArgumentError, ~r/cannot encode a Range struct/, fn ->
        JSON.encode(1..3)
      end
    end

    test "raises on unusable object keys" do
      assert_raise ArgumentError, ~r/as an object key/, fn -> JSON.encode(%{{1, 2} => "x"}) end
    end
  end

  test "round-trips through a real JSON parser" do
    value = %{
      "type" => "fill",
      "source" => "parcels",
      "paint" => %{"fill-color" => "#f00", "fill-opacity" => 0.5},
      "filter" => ["==", ["get", "zone"], "R1"],
      "metadata" => %{"note" => ~s(quotes " and \\ backslashes)}
    }

    assert Jason.decode!(JSON.encode(value)) == value
  end
end
