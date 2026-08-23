import Config

config :demo, DemoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: []],
  pubsub_server: Demo.PubSub

config :hologram, client_stacktraces: true

import_config "#{config_env()}.exs"
