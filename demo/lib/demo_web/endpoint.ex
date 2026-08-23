defmodule DemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :demo

  # Hologram writes its bundles into priv/static/hologram, so that directory
  # has to be served alongside the app's own static files.
  plug Plug.Static,
    at: "/",
    from: :demo,
    gzip: false,
    only: ["assets", "hologram", "favicon.ico"]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # Hologram reads and writes the session from its commands, so a session plug
  # has to be configured even in an app that stores nothing in it itself.
  plug Plug.Session,
    store: :cookie,
    key: "_demo_key",
    signing_salt: "kQ3Zt1Vw",
    same_site: "Lax"

  # Hologram's router must come before the application's own, so it can answer
  # for the routes its pages declare.
  plug Hologram.Router
  plug DemoWeb.Router
end
