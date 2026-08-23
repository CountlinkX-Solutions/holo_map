defmodule HoloMap.RenderCase do
  @moduledoc """
  Renders `HoloMap` components server-side and exposes what they emitted.

  Hologram's JS interop is a no-op on the server, so the browser half of this
  library cannot be reached from `ExUnit`. What *can* be tested is the half
  that decides what the browser sees: the `data-hm-*` attributes each component
  renders. These helpers render a component tree through Hologram's own
  renderer and hand back those attributes, already decoded.
  """

  use ExUnit.CaseTemplate

  alias Hologram.Server
  alias Hologram.Template.Renderer

  using do
    quote do
      import HoloMap.RenderCase
    end
  end

  @doc """
  Renders `module` with `props`, inside a `HoloMap.Map` that supplies context.

  Definition components require the map's cid from context, so they cannot be
  rendered standalone — which is the behaviour `definition_outside_map/2`
  exists to assert.
  """
  def render_def(module, props, children \\ []) do
    map_props = [{"cid", [text: "test_map"]}, {"style", [text: "https://example.com/style.json"]}]
    child = {:component, module, props_dom(props), children}

    {html, _registry, _server} =
      Renderer.render_dom(
        {:component, HoloMap.Map, map_props, [child]},
        %Renderer.Env{},
        %Server{}
      )

    html
  end

  @doc "Renders `module` with `props` on its own."
  def render(module, props, children \\ []) do
    {html, _registry, _server} =
      Renderer.render_dom(
        {:component, module, props_dom(props), children},
        %Renderer.Env{},
        %Server{}
      )

    html
  end

  @doc """
  Pulls the decoded `data-hm-spec` of the definition with the given key.

  Returns `nil` when no definition carries that key, which distinguishes "the
  component rendered nothing" from "the component rendered an empty spec".
  """
  def spec_for(html, key) do
    attribute(html, key, "data-hm-spec")
  end

  @doc "Pulls the decoded `data-hm-events` of the definition with the given key."
  def events_for(html, key) do
    attribute(html, key, "data-hm-events")
  end

  defp attribute(html, key, name) do
    # The definition elements are flat and attribute order is stable, so a
    # targeted regex is enough here and avoids pulling in an HTML parser for
    # assertions about strings this library itself produced.
    pattern = ~r/data-hm-key="#{Regex.escape(key)}"[^>]*?#{name}="([^"]*)"/

    case Regex.run(pattern, html) do
      [_full, encoded] -> encoded |> HtmlEntities.decode() |> Jason.decode!()
      nil -> nil
    end
  end

  # Binaries default to the text path, which is what a literal attribute in a
  # template produces — and which Hologram HTML-escapes. Wrap a binary in
  # `{:expr, value}` to send it down the expression path instead.
  defp props_dom(props) do
    Enum.map(props, fn
      {name, {:expr, value}} -> {to_string(name), [expression: {value}]}
      {name, value} when is_binary(value) -> {to_string(name), [text: value]}
      {name, value} -> {to_string(name), [expression: {value}]}
    end)
  end
end
