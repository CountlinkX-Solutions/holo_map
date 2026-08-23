defmodule HoloMap.EventTest do
  use ExUnit.Case, async: true

  doctest HoloMap.Event

  alias HoloMap.Event

  test "a bare atom targets the page" do
    assert Event.normalize(:clicked) == %{
             "action" => "clicked",
             "target" => "page",
             "params" => %{}
           }
  end

  test "nil means no listener at all" do
    assert Event.normalize(nil) == nil
  end

  test "longhand maps carry a target and params" do
    assert Event.normalize(%{action: :clicked, target: "sidebar", params: %{layer: "parcels"}}) ==
             %{
               "action" => "clicked",
               "target" => "sidebar",
               "params" => %{"layer" => "parcels"}
             }
  end

  test "keyword lists work wherever maps do" do
    assert Event.normalize(action: :clicked, target: "sidebar") ==
             %{"action" => "clicked", "target" => "sidebar", "params" => %{}}
  end

  test "string keys are accepted alongside atom keys" do
    assert Event.normalize(%{"action" => "clicked"}) ==
             %{"action" => "clicked", "target" => "page", "params" => %{}}
  end

  test "params keys are normalised to strings" do
    # Hologram turns JS object keys back into atoms on the way in, so an atom
    # key and a string key would otherwise collapse into one entry there.
    assert %{"params" => %{"a" => 1, "b" => 2}} =
             Event.normalize(%{action: :x, params: %{:a => 1, "b" => 2}})
  end

  test "raises when no action is given" do
    assert_raise ArgumentError, ~r/must have an :action key/, fn ->
      Event.normalize(%{target: "sidebar"})
    end
  end

  test "raises on an unusable handler value" do
    assert_raise ArgumentError, ~r/expected an action name atom/, fn ->
      Event.normalize("clicked")
    end
  end
end
