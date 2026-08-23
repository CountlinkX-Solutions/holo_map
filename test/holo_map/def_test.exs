defmodule HoloMap.DefTest do
  use ExUnit.Case, async: true

  doctest HoloMap.Def

  alias HoloMap.Def

  describe "spec/1" do
    test "drops nil entries" do
      assert Def.spec(%{"a" => 1, "b" => nil}) == ~s({"a":1})
    end

    test "keeps false" do
      assert Def.spec(%{"interactive" => false}) == ~s({"interactive":false})
    end
  end

  describe "events/1" do
    test "drops unset handlers instead of encoding null" do
      # A stable attribute string is what stops the reconciler from rebinding
      # listeners on every unrelated re-render.
      assert Def.events(click: nil, mouseleave: nil) == "{}"
    end

    test "encodes the handlers that are set" do
      assert Def.events(click: :picked) ==
               ~s({"click":{"action":"picked","params":{},"target":"page"}})
    end
  end

  describe "visibility/2" do
    test "folds the visible prop into the layout map" do
      assert Def.visibility(%{}, true) == %{"visibility" => "visible"}
      assert Def.visibility(%{}, false) == %{"visibility" => "none"}
    end

    test "leaves layout alone when visible is unset" do
      # So a caller writing layout: %{visibility: ...} by hand is not overridden.
      assert Def.visibility(%{"visibility" => "none"}, nil) == %{"visibility" => "none"}
    end
  end

  test "context_key is namespaced by module" do
    assert Def.context_key() == {HoloMap.Map, :cid}
  end
end
