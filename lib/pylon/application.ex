defmodule Pylon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Register AI tools
    register_ai_tools()

    children = [
      PylonWeb.Telemetry,
      Pylon.Repo,
      {DNSCluster, query: Application.get_env(:pylon, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pylon.PubSub},
      # AI Agent supervision tree
      {Registry, keys: :unique, name: Pylon.AgentRegistry},
      Pylon.AI.AgentSupervisor,
      # Start a worker by calling: Pylon.Worker.start_link(arg)
      # {Pylon.Worker, arg},
      # Start to serve requests, typically the last entry
      PylonWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pylon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp register_ai_tools do
    Pylon.AI.Toolset.register_tools([
      Pylon.AI.Tools.Calculator,
      Pylon.AI.Tools.Echo
    ])
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PylonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
