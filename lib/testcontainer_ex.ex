defmodule TestcontainerEx do
  @moduledoc """
  Public API for TestcontainerEx.

  This module is a thin facade that delegates to the GenServer
  (`TestcontainerEx.Server`) and domain modules.
  """

  alias TestcontainerEx.{
    Container.Config,
    Docker.Engine,
    Server
  }

  @timeout 300_000

  # ── Lifecycle ─────────────────────────────────────────────────────

  def start_link(options \\ []), do: Server.start_link(options)
  def start(options \\ []), do: Server.start(options)

  # ── Container operations ──────────────────────────────────────────

  def start_container(config_builder, name \\ __MODULE__) do
    GenServer.call(name, {:start_container, config_builder}, @timeout)
  end

  def stop_container(container_id, name \\ __MODULE__) when is_binary(container_id) do
    GenServer.call(name, {:stop_container, container_id}, @timeout)
  end

  # ── Host/port resolution ──────────────────────────────────────────

  def get_host, do: GenServer.call(__MODULE__, :get_host, @timeout)

  def get_host(%Config{} = container), do: get_host(container, __MODULE__)
  def get_host(name) when is_atom(name), do: GenServer.call(name, :get_host, @timeout)

  def get_host(%Config{} = container, name) do
    mode = GenServer.call(name, :get_connection_mode, @timeout)

    if mode == :container_ip and is_binary(container.ip_address) and container.ip_address != "" and
         is_nil(container.network) do
      container.ip_address
    else
      GenServer.call(name, :get_host, @timeout)
    end
  end

  def get_port(%Config{} = container, port), do: get_port(container, port, __MODULE__)

  def get_port(%Config{} = container, port, name) do
    mode = GenServer.call(name, :get_connection_mode, @timeout)

    if mode == :container_ip and is_binary(container.ip_address) and container.ip_address != "" and
         is_nil(container.network) do
      port
    else
      Config.mapped_port(container, port)
    end
  end

  # ── Network operations ────────────────────────────────────────────

  def create_network(network_name, name \\ __MODULE__) do
    GenServer.call(name, {:create_network, network_name}, @timeout)
  end

  def remove_network(network_name, name \\ __MODULE__) do
    GenServer.call(name, {:remove_network, network_name}, @timeout)
  end

  # ── Compose operations ────────────────────────────────────────────

  def start_compose(config, name \\ __MODULE__) do
    GenServer.call(name, {:start_compose, config}, @timeout)
  end

  def stop_compose(compose_env, name \\ __MODULE__) do
    GenServer.call(name, {:stop_compose, compose_env}, @timeout)
  end

  # ── Engine detection ──────────────────────────────────────────────

  def container_engine, do: Engine.detect()
  def running_in_container?, do: Config.running_in_container?()

  # ── Debugging ─────────────────────────────────────────────────────

  defdelegate debug_status, to: TestcontainerEx.Debug, as: :status
  defdelegate debug_inspect(container), to: TestcontainerEx.Debug, as: :inspect_container
  defdelegate debug_summarize(container), to: TestcontainerEx.Debug, as: :summarize
  defdelegate debug_list_containers, to: TestcontainerEx.Debug, as: :list_containers
  defdelegate debug_list_networks, to: TestcontainerEx.Debug, as: :list_networks

  # ── Ryuk ──────────────────────────────────────────────────────────

  defdelegate ryuk_privileged?(properties), to: TestcontainerEx.Ryuk, as: :privileged?

  # ── Connection ────────────────────────────────────────────────────

  def connected?(name \\ __MODULE__), do: Server.connected?(name)
  def stop(name \\ __MODULE__), do: Server.stop(name)

  @doc """
  Returns `true` when running inside a container (Docker, Podman, Kubernetes).

  Accepts optional overrides for the `.dockerenv` path, cgroup path,
  Kubernetes secrets path, and Podman containerenv path
  (useful for testing on non-Linux hosts).
  """
  def running_in_container?(
        dockerenv_path,
        cgroup_path,
        k8s_secrets_path \\ "/var/run/secrets/kubernetes.io",
        containerenv_path \\ "/.containerenv"
      ) do
    Config.running_in_container?(dockerenv_path, cgroup_path, k8s_secrets_path, containerenv_path)
  end

  @doc """
  Parses the default gateway IP from `/proc/net/route` content.

  Returns `{:ok, ip_string}` or `{:error, :no_default_route}`.
  """
  def parse_gateway_from_proc_route(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.find(fn
      [_, "00000000", gateway | _] when gateway != "00000000" -> true
      _ -> false
    end)
    |> case do
      [_, "00000000", gateway | _] ->
        ip =
          gateway
          |> String.to_integer(16)
          |> :binary.encode_unsigned(:little)
          |> :binary.bin_to_list()

        {:ok, Enum.join(ip, ".")}

      _ ->
        {:error, :no_default_route}
    end
  end
end
