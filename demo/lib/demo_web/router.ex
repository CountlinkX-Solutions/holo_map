defmodule DemoWeb.Router do
  @moduledoc """
  Fallback router for anything Hologram's router did not answer.

  Every page in this demo is a Hologram page, so in practice this only ever
  produces the 404.
  """

  use Phoenix.Router

  match :*, "/*path", DemoWeb.NotFoundController, :call
end
