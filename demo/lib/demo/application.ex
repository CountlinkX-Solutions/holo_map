defmodule Demo.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Demo.PubSub},
      DemoWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Demo.Supervisor)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    DemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
