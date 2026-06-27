defmodule TestcontainerEx.Server do
  @moduledoc """
  GenServer that manages the TestcontainerEx lifecycle.

  State holds the connection, session metadata, and tracked resources
  (containers, networks, compose environments) for cleanup on termination.
  """

  use GenServer

  require Logger

  alias TestcontainerEx.{
    Connection,
    Container.Config,
    Container.Lifecycle,
    Engine,
    Network,
    Ryuk,
    TaskSupervisor,
    Util.PropertiesParser
  }

  alias TestcontainerEx.Compose.Cli

  # ── Public API ────────────────────────────────────────────────────

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  def start(options \\ []) do
    GenServer.start(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  @doc """
  Returns the engine currently in use by the given server.

  Returns an engine atom (`:docker`, `:podman`, `:colima`, `:minikube`,
  `:apple_container`) or `:auto` if no explicit engine was selected.
  """
  def get_engine(name \\ __MODULE__) do
    GenServer.call(name, :get_engine)
  end

  @doc """
  Reconnects the server to a different container engine at runtime.

  This stops all tracked containers, tears down the existing connection,
  and re-initializes with the specified engine.

  ## Options

    * `:engine` — the engine to switch to (e.g., `:docker`, `:podman`, `:colima`,
      `:minikube`, `:apple_container`, or `:auto` for auto-detection)

  ## Examples

      # Switch to Podman
      TestcontainerEx.reconnect(engine: :podman)

      # Switch back to auto-detection
      TestcontainerEx.reconnect(engine: :auto)

  """
  def reconnect(options) when is_list(options) do
    name = Keyword.get(options, :name, __MODULE__)
    options = Keyword.delete(options, :name)
    GenServer.call(name, {:reconnect, options})
  end

  @doc """
  Returns true if the server has a working Docker connection.
  """
  def connected?(name \\ __MODULE__) do
    GenServer.call(name, :connected?)
  end

  @doc """
  Stops the GenServer.
  """
  def stop(name \\ __MODULE__) do
    GenServer.stop(name)
  end

  # ── GenServer Callbacks ───────────────────────────────────────────

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    setup(options)
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, !is_nil(state.conn), state}
  end

  @impl true
  def handle_call(:get_engine, _from, state) do
    {:reply, state.engine, state}
  end

  @impl true
  def handle_call({:reconnect, options}, _from, state) do
    engine_opt = Keyword.get(options, :engine, :auto)

    # Stop tracked containers before switching
    Enum.each(state.containers, &Lifecycle.stop_container(&1, state.conn))
    Enum.each(state.compose_envs, &Cli.down(&1.compose))
    Enum.each(state.networks, &Network.remove(&1, state.conn))

    # Clear the persistent-term cache so auto-detection re-runs
    :persistent_term.erase({Engine, :cached_engine})

    # Build new options for connection, preserving the server name
    conn_options = [engine: engine_opt, name: state.server_name]

    case Connection.get_connection(conn_options) do
      {conn, docker_host_url, docker_host} ->
        {:ok, properties} = PropertiesParser.read_property_sources()

        with {:ok, docker_hostname} <- resolve_docker_hostname(docker_host_url, conn, properties),
             use_container_ip <- should_use_container_ip?(docker_hostname),
             {:ok} <- Ryuk.start(conn, state.session_id, properties, docker_host, docker_hostname) do
          resolved_engine = Engine.detect()

          new_state = %{
            state
            | conn: conn,
              docker_hostname: docker_hostname,
              use_container_ip: use_container_ip,
              properties: properties,
              engine: engine_opt,
              containers: MapSet.new(),
              networks: MapSet.new(),
              compose_envs: []
          }

          Logger.info(
            "TestcontainerEx reconnected to #{resolved_engine} (requested: #{engine_opt})"
          )

          {:reply, {:ok, resolved_engine}, new_state}
        end

      {:error, reason} ->
        Logger.warning(
          "Failed to reconnect to #{engine_opt}: #{inspect(reason)}. " <>
            "Server is now disconnected."
        )

        disconnected_state = %{
          state
          | conn: nil,
            docker_hostname: nil,
            use_container_ip: false,
            properties: %{},
            engine: engine_opt,
            containers: MapSet.new(),
            networks: MapSet.new(),
            compose_envs: []
        }

        {:reply, {:error, reason}, disconnected_state}
    end
  end

  @impl true
  def handle_call({:start_container, _builder}, _from, %{conn: nil} = state) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:start_container, builder}, from, state) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      result = Lifecycle.start_container(builder, state.conn, state)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:start_containers, builders}, from, state) when is_list(builders) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      result = Lifecycle.start_containers(builders, state.conn, state)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:list_containers, _from, state) do
    {:reply, MapSet.to_list(state.containers), state}
  end

  @impl true
  def handle_call(:list_networks, _from, state) do
    {:reply, MapSet.to_list(state.networks), state}
  end

  @impl true
  def handle_call({:stop_container, _container_id}, _from, %{conn: nil} = state) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:stop_container, container_id}, _from, state) do
    result = Lifecycle.stop_container(container_id, state.conn)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:stop_containers, container_ids}, _from, %{conn: nil} = state)
      when is_list(container_ids) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:stop_containers, container_ids}, _from, state) when is_list(container_ids) do
    result = Lifecycle.stop_containers(container_ids, state.conn)
    {:reply, result, untrack_containers(state, container_ids)}
  end

  @impl true
  def handle_call(:get_host, _from, state) do
    {:reply, state.docker_hostname, state}
  end

  @impl true
  def handle_call(:get_connection_mode, _from, state) do
    {:reply, if(state.use_container_ip, do: :container_ip, else: :standard), state}
  end

  @impl true
  def handle_call({:inspect_container, _container_id}, _from, %{conn: nil} = state) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:inspect_container, container_id}, _from, state) do
    result = Lifecycle.inspect_container(container_id, state.conn)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:container_logs, _container_id, _opts}, _from, %{conn: nil} = state) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:container_logs, container_id, opts}, _from, state) do
    result = Lifecycle.container_logs(container_id, state.conn, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:exec, _container_id, _command}, _from, %{conn: nil} = state) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:exec, container_id, command}, _from, state) do
    result = Lifecycle.exec(container_id, command, state.conn)
    {:reply, result, state}
  end

  @impl true
  def handle_call(
        {:monitor_container, _container_id, _predicate, _opts},
        _from,
        %{conn: nil} = state
      ) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:monitor_container, container_id, predicate, opts}, from, state) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      result = Lifecycle.monitor_container(container_id, predicate, state.conn, opts)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:create_network, _network_name}, _from, %{conn: nil} = state) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:create_network, network_name}, _from, state) do
    result = Network.create(network_name, state.conn)
    {:reply, result, track_network(state, network_name)}
  end

  @impl true
  def handle_call({:remove_network, _network_name}, _from, %{conn: nil} = state) do
    {:reply, {:error, TestcontainerEx.Error.not_connected()}, state}
  end

  @impl true
  def handle_call({:remove_network, network_name}, _from, state) do
    result = Network.remove(network_name, state.conn)
    {:reply, result, untrack_network(state, network_name)}
  end

  @impl true
  def handle_call({:start_compose, compose}, from, state) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      result = Cli.up(compose)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:stop_compose, compose_env}, _from, state) do
    result = Cli.down(compose_env.compose)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:track_container, container_id, image}, state) do
    {:noreply,
     %{
       state
       | containers: MapSet.put(state.containers, container_id),
         images: MapSet.put(state.images, image)
     }}
  end

  @impl true
  def handle_cast({:track_image, image}, state) do
    {:noreply, %{state | images: MapSet.put(state.images, image)}}
  end

  @impl true
  def handle_cast({:track_compose_env, compose_env}, state) do
    {:noreply, %{state | compose_envs: [compose_env | state.compose_envs]}}
  end

  @impl true
  def handle_cast({:untrack_compose_env, compose_env}, state) do
    {:noreply, %{state | compose_envs: List.delete(state.compose_envs, compose_env)}}
  end

  @impl true
  def handle_info({:track_container, container_id, image}, state) do
    {:noreply,
     %{
       state
       | containers: MapSet.put(state.containers, container_id),
         images: MapSet.put(state.images, image)
     }}
  end

  @impl true
  def handle_info({:track_image, image}, state) do
    {:noreply, %{state | images: MapSet.put(state.images, image)}}
  end

  @impl true
  def handle_info({:track_compose_env, compose_env}, state) do
    {:noreply, %{state | compose_envs: [compose_env | state.compose_envs]}}
  end

  @impl true
  def handle_info({:untrack_compose_env, compose_env}, state) do
    {:noreply, %{state | compose_envs: List.delete(state.compose_envs, compose_env)}}
  end

  @impl true
  def handle_info({:list_containers, from}, state) do
    GenServer.reply(from, MapSet.to_list(state.containers))
    {:noreply, state}
  end

  @impl true
  def handle_info({:list_networks, from}, state) do
    GenServer.reply(from, MapSet.to_list(state.networks))
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{conn: nil}), do: :ok

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.containers, &Lifecycle.stop_container(&1, state.conn))
    Enum.each(state.compose_envs, &Cli.down(&1.compose))
    Enum.each(state.networks, &Network.remove(&1, state.conn))
    :ok
  end

  # ── Private ───────────────────────────────────────────────────────

  defp setup(options) do
    session_id =
      :crypto.hash(:sha, "#{inspect(self())}#{DateTime.utc_now() |> DateTime.to_string()}")
      |> Base.encode16()

    engine_opt = Keyword.get(options, :engine, :auto)
    server_name = Keyword.get(options, :name, __MODULE__)

    state = %{
      conn: nil,
      docker_hostname: nil,
      use_container_ip: false,
      session_id: session_id,
      properties: %{},
      networks: MapSet.new(),
      containers: MapSet.new(),
      images: MapSet.new(),
      compose_envs: [],
      engine: engine_opt,
      server_name: server_name
    }

    initialize_connection(options, state)
  end

  defp initialize_connection(options, state) do
    case Connection.get_connection(options) do
      {conn, docker_host_url, docker_host} ->
        {:ok, properties} = PropertiesParser.read_property_sources()

        with {:ok, docker_hostname} <- resolve_docker_hostname(docker_host_url, conn, properties),
             use_container_ip <- should_use_container_ip?(docker_hostname),
             {:ok} <- Ryuk.start(conn, state.session_id, properties, docker_host, docker_hostname) do
          engine = Engine.detect()

          if use_container_ip do
            Logger.info(
              "TestcontainerEx initialized with #{engine} in container networking mode (using container IPs directly)"
            )
          else
            Logger.info("TestcontainerEx initialized with #{engine}")
          end

          {:ok,
           %{
             state
             | conn: conn,
               docker_hostname: docker_hostname,
               use_container_ip: use_container_ip,
               properties: properties
           }}
        end

      {:error, reason} ->
        Logger.warning(
          "No container engine available at startup: #{inspect(reason)}. " <>
            "TestcontainerEx will start in disconnected mode. " <>
            "Call TestcontainerEx.start_link/1 again after the engine is running."
        )

        {:ok, %{state | properties: %{}, conn: nil}}
    end
  end

  defp resolve_docker_hostname(docker_host_url, conn, properties) do
    host_override =
      Map.get(properties, "tc.host.override") ||
        System.get_env("TESTCONTAINERS_HOST_OVERRIDE")

    if host_override do
      {:ok, host_override}
    else
      do_resolve_hostname(docker_host_url, conn)
    end
  end

  defp do_resolve_hostname(docker_host_url, conn) do
    case URI.parse(docker_host_url) do
      %URI{scheme: "http"} -> {:ok, URI.parse(docker_host_url).host}
      %URI{scheme: "https"} -> {:ok, URI.parse(docker_host_url).host}
      %URI{scheme: "http+unix"} -> resolve_unix_hostname(conn)
      %URI{scheme: "apple-container"} -> {:ok, "localhost"}
    end
  end

  defp resolve_unix_hostname(conn) do
    if Config.running_in_container?() do
      case Network.bridge_gateway(conn) do
        {:ok, gateway} -> {:ok, gateway}
        {:error, _} -> resolve_from_proc_route()
      end
    else
      {:ok, "localhost"}
    end
  end

  defp resolve_from_proc_route do
    case File.read("/proc/net/route") do
      {:ok, content} ->
        case parse_gateway(content) do
          {:ok, gateway} -> {:ok, gateway}
          {:error, _} -> {:ok, "localhost"}
        end

      {:error, _} ->
        {:ok, "localhost"}
    end
  end

  defp parse_gateway(content) do
    content
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.map(&String.split(&1, "\t"))
    |> Enum.find(fn
      [_iface, dest | _] -> dest == "00000000"
      _ -> false
    end)
    |> case do
      [_iface, _dest, hex | _] ->
        decode_hex_gateway(hex)

      _ ->
        {:error, :no_default_route}
    end
  end

  defp decode_hex_gateway(hex) when byte_size(hex) == 8 do
    {value, ""} = Integer.parse(hex, 16)
    a = Bitwise.band(value, 0xFF)
    b = Bitwise.band(Bitwise.bsr(value, 8), 0xFF)
    c = Bitwise.band(Bitwise.bsr(value, 16), 0xFF)
    d = Bitwise.band(Bitwise.bsr(value, 24), 0xFF)
    {:ok, "#{a}.#{b}.#{c}.#{d}"}
  end

  defp decode_hex_gateway(_), do: {:error, :invalid_gateway}

  defp should_use_container_ip?(docker_hostname) do
    if Config.running_in_container?() and docker_hostname != "localhost" do
      case :gen_tcp.connect(~c"#{docker_hostname}", 0, [], 2000) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          false

        {:error, :econnrefused} ->
          false

        {:error, reason} ->
          Logger.info(
            "Bridge gateway #{docker_hostname} unreachable (#{inspect(reason)}). Switching to container networking mode"
          )

          true
      end
    else
      false
    end
  end

  defp track_network(state, name), do: %{state | networks: MapSet.put(state.networks, name)}
  defp untrack_network(state, name), do: %{state | networks: MapSet.delete(state.networks, name)}

  defp untrack_containers(state, container_ids) when is_list(container_ids) do
    %{state | containers: Enum.reduce(container_ids, state.containers, &MapSet.delete(&2, &1))}
  end
end
