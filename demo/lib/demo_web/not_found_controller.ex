defmodule DemoWeb.NotFoundController do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Not found. Try / for the demo index.")
  end
end
