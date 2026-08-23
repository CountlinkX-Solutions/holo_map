import Config

config :demo, DemoWeb.Endpoint,
  # Dual-stack on purpose: `localhost` resolves to ::1 on many systems (and on
  # WSL), so a v4-only listener is reachable by curl — which falls back to
  # 127.0.0.1 — while the browser fails outright. On Linux an IPv6 "any"
  # listener accepts IPv4 connections too.
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || "4000")
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "demo_only_secret_key_base_at_least_64_bytes_long_0000000000000000000",
  server: true

# Hologram's client stacktraces are built on them, so they are worth their
# weight while developing.
config :demo, serve_sourcemaps: true

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
