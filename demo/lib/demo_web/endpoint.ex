defmodule DemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :demo

  # Sourcemaps are five times the size of the code they describe — 28 MB across
  # this demo's bundles — and only a browser with devtools open ever asks for
  # one. They stay available in development and are refused everywhere else.
  plug(:reject_sourcemaps)

  # Hologram names every bundle by content hash, so the bytes behind a given URL
  # never change. They can be cached for a year and never revalidated, which is
  # worth its own Plug.Static: /assets holds unhashed filenames that must keep
  # revalidating.
  #
  # gzip: true serves the pre-compressed files `mix assets.gzip` writes.
  # Bandit compresses responses on the fly, but Plug.Static answers with
  # send_file/3 and a sendfile cannot be compressed in flight — so a 1.06 MB
  # bundle goes out at 1.06 MB rather than the 0.26 MB it gzips to.
  plug(Plug.Static,
    at: "/hologram",
    from: {:demo, "priv/static/hologram"},
    gzip: true,
    cache_control_for_etags: "public, max-age=31536000, immutable"
  )

  plug(Plug.Static,
    at: "/",
    from: :demo,
    gzip: true,
    only: ["assets", "favicon.ico"]
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  # Hologram reads and writes the session from its commands, so a session plug
  # has to be configured even in an app that stores nothing in it itself.
  plug(Plug.Session,
    store: :cookie,
    key: "_demo_key",
    signing_salt: "kQ3Zt1Vw",
    same_site: "Lax"
  )

  # Hologram's router must come before the application's own, so it can answer
  # for the routes its pages declare.
  plug(Hologram.Router)
  plug(DemoWeb.Router)

  defp reject_sourcemaps(conn, _opts) do
    if String.ends_with?(conn.request_path, ".map") and
         not Application.get_env(:demo, :serve_sourcemaps, false) do
      conn
      |> Plug.Conn.send_resp(404, "")
      |> Plug.Conn.halt()
    else
      conn
    end
  end
end
