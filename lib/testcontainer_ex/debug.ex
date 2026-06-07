defmodule TestcontainerEx.Debug do
  @moduledoc """
  Runtime debugging and inspection helpers for TestcontainerEx.

  Provides functions to inspect container state, list running containers,
  dump configuration, and check connectivity — useful from `iex -S mix`
  or when debugging failing tests.

  ## Usage

      iex> TestcontainerEx.Debug.status()
      %{
        connected: true,
        engine: :docker,
        host: "localhost",
        container_ip_mode: false,
        session_id: "A1B2..."
      }

      iex> {:ok, container} = TestcontainerEx.start_container(redis)
      iex> TestcontainerEx.Debug.inspect_container(container)
      %{
        container_id: "abc123...",
        image: "redis:7.2-alpine",
        ports: [{6379, 55123}],
        ip_address: "172.17.0.3",
        environment: %{"REDIS_PASSWORD" => "..."},
        labels: %{...}
      }

      iex> TestcontainerEx.Debug.list_containers()
      ["abc123...", "def456..."]
  """

  alias TestcontainerEx.Server
  alias TestcontainerEx.Container.Config

  @doc """
  Returns a summary of the TestcontainerEx server status.

  Includes connection state, detected engine, host, and session ID.
  """
  @spec status() :: map()
  def status do
    connected = Server.connected?()

    base = %{
      connected: connected,
      engine: TestcontainerEx.container_engine(),
      running_in_container: Config.running_in_container?()
    }

    if connected do
      host = TestcontainerEx.get_host()
      mode = GenServer.call(TestcontainerEx, :get_connection_mode, 30_000)

      Map.merge(base, %{
        host: host,
        container_ip_mode: mode == :container_ip
      })
    else
      base
    end
  end

  @doc """
  Returns a human-readable map of a container's runtime state.

  Useful for debugging from IEx or logging container details.
  """
  @spec inspect_container(Config.t()) :: map()
  def inspect_container(%Config{} = container) do
    %{
      container_id: container.container_id,
      image: container.image,
      ports: container.exposed_ports,
      ip_address: container.ip_address,
      environment: container.environment,
      labels: container.labels,
      network: container.network,
      network_mode: container.network_mode,
      hostname: container.hostname,
      auto_remove: container.auto_remove,
      privileged: container.privileged,
      reuse: container.reuse,
      wait_strategies: Enum.map(container.wait_strategies, &strategy_name/1)
    }
  end

  @doc """
  Returns the list of tracked container IDs from the server state.

  These are containers managed by the current TestcontainerEx session.
  """
  @spec list_containers() :: [String.t()]
  def list_containers do
    GenServer.call(TestcontainerEx, :list_containers, 30_000)
  end

  @doc """
  Returns the list of tracked network names from the server state.
  """
  @spec list_networks() :: [String.t()]
  def list_networks do
    GenServer.call(TestcontainerEx, :list_networks, 30_000)
  end

  @doc """
  Returns a formatted string summary of a container for quick console inspection.
  """
  @spec summarize(Config.t()) :: String.t()
  def summarize(%Config{} = container) do
    port_info =
      Enum.map_join(container.exposed_ports, ", ", fn
        {p, nil} -> "#{p}->auto"
        {p, h} -> "#{p}->#{h}"
      end)

    "#{container.image} [#{container.container_id}] ports: #{port_info} ip: #{container.ip_address || "n/a"}"
  end

  # ── Private ───────────────────────────────────────────────────────

  defp strategy_name(%{__struct__: mod}), do: mod
  defp strategy_name(other), do: other
end
