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
  def running_in_container?, do: Container.running_in_container?()
end
