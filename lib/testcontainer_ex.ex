defmodule TestcontainerEx do
  @moduledoc """
  Public API for TestcontainerEx.

  This module is a thin facade that delegates to the GenServer
  (`TestcontainerEx.Server`) and domain modules.

  ## Engine Selection

  By default, TestcontainerEx auto-detects the container engine. You can
  explicitly select an engine in three ways (in order of precedence):

  ### 1. Runtime override (highest priority)

  Use `set_engine/1` to switch engines at runtime, per-process:

      TestcontainerEx.set_engine(:podman)
      TestcontainerEx.container_engine() # => :podman

  To reset back to auto-detection:

      TestcontainerEx.clear_engine()

  ### 2. Via `start_link/1` option

      TestcontainerEx.start_link(engine: :docker)

  ### 3. Via `CONTAINER_ENGINE` environment variable

      CONTAINER_ENGINE=docker mix test

  ### Runtime reconnection

  Use `reconnect/1` to switch engines on a running server. This stops all
  tracked containers and re-initializes the connection:

      TestcontainerEx.reconnect(engine: :podman)

  Supported engine values:

    * `:auto` — auto-detect (default)
    * `:docker` — Docker Desktop, Colima, or socket-based Docker
    * `:podman` — Podman socket or container env
    * `:colima` — Colima only
    * `:minikube` — Minikube only
    * `:apple_container` — Apple Container only
  """

  alias TestcontainerEx.{
    Container.Config,
    Engine,
    Error,
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

  @doc """
  Starts multiple containers.

  Accepts a list of config builders and returns `{:ok, containers}` only when
  all containers start successfully. On failure, returns `{:error, results}`
  where `results` contains per-container `{:ok, container}` or `{:error, reason}`
  entries in the same order as the input.
  """
  def start_containers(config_builders, name \\ __MODULE__) when is_list(config_builders) do
    GenServer.call(name, {:start_containers, config_builders}, @timeout)
  end

  @doc """
  Convenience alias for `start_container/2`.
  """
  def create_container(config_builder, name \\ __MODULE__),
    do: start_container(config_builder, name)

  @doc """
  Convenience alias for `start_containers/2`.
  """
  def create_containers(config_builders, name \\ __MODULE__),
    do: start_containers(config_builders, name)

  @doc """
  Convenience alias for `start_container/2`.
  """
  def run_container(config_builder, name \\ __MODULE__), do: start_container(config_builder, name)

  @doc """
  Convenience alias for `start_containers/2`.
  """
  def run_containers(config_builders, name \\ __MODULE__),
    do: start_containers(config_builders, name)

  @doc """
  Stops multiple containers.

  Returns `{:ok, results}` with one result per container ID. Nonexistent
  containers are treated as already stopped by the Docker API.
  """
  def stop_containers(container_ids, name \\ __MODULE__) when is_list(container_ids) do
    GenServer.call(name, {:stop_containers, container_ids}, @timeout)
  end

  @doc """
  Stops a container and waits until Docker no longer reports it running.
  """
  def stop_container(container_id, name \\ __MODULE__) when is_binary(container_id) do
    GenServer.call(name, {:stop_container, container_id}, @timeout)
  end

  @doc """
  Returns the latest Docker inspect result for a container ID.
  """
  def inspect_container(container_id, name \\ __MODULE__) when is_binary(container_id) do
    GenServer.call(name, {:inspect_container, container_id}, @timeout)
  end

  @doc """
  Returns container logs.

  Options include `:stdout`, `:stderr`, `:timestamps`, `:tail`, `:since`,
  `:until_time`, and `:follow`.
  """
  def container_logs(container_id, options \\ [], name \\ __MODULE__)
      when is_binary(container_id) do
    GenServer.call(name, {:container_logs, container_id, options}, @timeout)
  end

  @doc """
  Executes a command inside a running container.
  """
  def exec(container_id, command, name \\ __MODULE__)
      when is_binary(container_id) and is_list(command) do
    GenServer.call(name, {:exec, container_id, command}, @timeout)
  end

  @doc """
  Monitors a container until a predicate returns `{:ok, value}` or the timeout elapses.

  The predicate receives the latest inspected container and must return `{:ok, value}`
  to succeed or `{:error, reason}` to retry.
  """
  def monitor_container(container_id, predicate, options \\ [], name \\ __MODULE__)
      when is_binary(container_id) and is_function(predicate, 1) and is_list(options) do
    GenServer.call(name, {:monitor_container, container_id, predicate, options}, @timeout)
  end

  @doc """
  Starts a container asynchronously. Returns a `Task` that resolves to
  `{:ok, container}` or `{:error, TestcontainerEx.Error.t()}`.

  Useful for starting multiple containers in parallel during test setup.

  ## Example

      task_a = TestcontainerEx.start_container_async(RedisContainer.new())
      task_b = TestcontainerEx.start_container_async(PostgresContainer.new())

      {:ok, redis}    = TestcontainerEx.await_container(task_a, 60_000)
      {:ok, postgres} = TestcontainerEx.await_container(task_b, 60_000)
  """
  @spec start_container_async(struct()) :: Task.t()
  def start_container_async(config_builder) do
    Task.async(fn -> start_container(config_builder) end)
  end

  @doc """
  Awaits the result of `start_container_async/1`.

  Returns `{:ok, container}` on success or `{:error, TestcontainerEx.Error.t()}`
  on failure. Raises if the task does not complete within `timeout_ms`.
  """
  @spec await_container(Task.t(), integer()) :: {:ok, Config.t()} | {:error, Error.t()}
  def await_container(%Task{} = task, timeout_ms \\ 120_000) do
    Task.await(task, timeout_ms)
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
      case GenServer.call(name, :get_host, @timeout) do
        nil -> "localhost"
        host -> host
      end
    end
  catch
    :exit, {:noproc, _} -> "localhost"
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
  catch
    :exit, {:noproc, _} -> Config.mapped_port(container, port)
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

  defdelegate set_engine(engine), to: Engine, as: :set_engine
  defdelegate clear_engine(), to: Engine, as: :clear_engine
  defdelegate get_engine(name), to: Server, as: :get_engine
  defdelegate reconnect(options), to: Server, as: :reconnect

  # ── Custom container ──────────────────────────────────────────────

  defdelegate custom_container(image),
    to: TestcontainerEx.CustomContainer,
    as: :new

  defdelegate custom_container_from_config(config),
    to: TestcontainerEx.CustomContainer,
    as: :from_config

  defdelegate custom_container_runtime_info(container),
    to: TestcontainerEx.CustomContainer,
    as: :runtime_info

  defdelegate custom_container_endpoint(container, port),
    to: TestcontainerEx.CustomContainer,
    as: :endpoint

  defdelegate custom_container_endpoint_url(container, port, scheme),
    to: TestcontainerEx.CustomContainer,
    as: :endpoint_url

  # ── Container control (low-level Docker Engine API) ───────────────

  defdelegate container_start(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :start

  defdelegate container_start(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :start

  defdelegate container_stop(container_id, timeout, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :stop

  defdelegate container_stop(container_id, timeout),
    to: TestcontainerEx.Engine.Control,
    as: :stop

  defdelegate container_stop(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :stop

  defdelegate container_restart(container_id, timeout, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :restart

  defdelegate container_restart(container_id, timeout),
    to: TestcontainerEx.Engine.Control,
    as: :restart

  defdelegate container_restart(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :restart

  defdelegate container_kill(container_id, signal, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :kill

  defdelegate container_kill(container_id, signal),
    to: TestcontainerEx.Engine.Control,
    as: :kill

  defdelegate container_kill(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :kill

  defdelegate container_pause(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :pause

  defdelegate container_pause(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :pause

  defdelegate container_unpause(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :unpause

  defdelegate container_unpause(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :unpause

  defdelegate container_remove(container_id, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :remove

  defdelegate container_remove(container_id, opts),
    to: TestcontainerEx.Engine.Control,
    as: :remove

  defdelegate container_remove(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :remove

  defdelegate container_rename(container_id, new_name, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :rename

  defdelegate container_rename(container_id, new_name),
    to: TestcontainerEx.Engine.Control,
    as: :rename

  defdelegate container_update(container_id, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :update

  defdelegate container_update(container_id, opts),
    to: TestcontainerEx.Engine.Control,
    as: :update

  defdelegate container_inspect(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :inspect_container

  defdelegate container_inspect(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :inspect_container

  defdelegate container_state(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :state

  defdelegate container_state(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :state

  defdelegate container_running?(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :running?

  defdelegate container_running?(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :running?

  defdelegate container_wait(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :wait

  defdelegate container_wait(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :wait

  defdelegate container_stats(container_id, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :stats

  defdelegate container_stats(container_id, opts),
    to: TestcontainerEx.Engine.Control,
    as: :stats

  defdelegate container_stats(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :stats

  defdelegate container_top(container_id, ps_args, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :top

  defdelegate container_top(container_id, ps_args),
    to: TestcontainerEx.Engine.Control,
    as: :top

  defdelegate container_top(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :top

  defdelegate container_upload(container_id, path, source, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :upload

  defdelegate container_upload(container_id, path, source),
    to: TestcontainerEx.Engine.Control,
    as: :upload

  defdelegate container_download(container_id, path, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :download

  defdelegate container_download(container_id, path),
    to: TestcontainerEx.Engine.Control,
    as: :download

  defdelegate container_download_file(container_id, path, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :download_file

  defdelegate container_download_file(container_id, path),
    to: TestcontainerEx.Engine.Control,
    as: :download_file

  defdelegate container_commit(container_id, repo_tag, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :commit

  defdelegate container_commit(container_id, repo_tag, opts),
    to: TestcontainerEx.Engine.Control,
    as: :commit

  defdelegate container_commit(container_id, repo_tag),
    to: TestcontainerEx.Engine.Control,
    as: :commit

  defdelegate container_export(container_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :export

  defdelegate container_export(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :export

  defdelegate container_resize(container_id, width, height, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :resize

  defdelegate container_resize(container_id, width, height),
    to: TestcontainerEx.Engine.Control,
    as: :resize

  defdelegate container_attach(container_id, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :attach

  defdelegate container_attach(container_id, opts),
    to: TestcontainerEx.Engine.Control,
    as: :attach

  defdelegate container_attach(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :attach

  defdelegate container_create(config, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :create

  defdelegate container_create(config),
    to: TestcontainerEx.Engine.Control,
    as: :create

  defdelegate container_create_named(name, config, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :create_named

  defdelegate container_create_named(name, config),
    to: TestcontainerEx.Engine.Control,
    as: :create_named

  defdelegate container_logs_raw(container_id, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :logs

  defdelegate container_logs_raw(container_id, opts),
    to: TestcontainerEx.Engine.Control,
    as: :logs

  defdelegate container_logs_raw(container_id),
    to: TestcontainerEx.Engine.Control,
    as: :logs

  defdelegate exec_create(container_id, command, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :create_exec

  defdelegate exec_create(container_id, command, opts),
    to: TestcontainerEx.Engine.Control,
    as: :create_exec

  defdelegate exec_create(container_id, command),
    to: TestcontainerEx.Engine.Control,
    as: :create_exec

  defdelegate exec_start(exec_id, opts, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :start_exec

  defdelegate exec_start(exec_id, opts),
    to: TestcontainerEx.Engine.Control,
    as: :start_exec

  defdelegate exec_start(exec_id),
    to: TestcontainerEx.Engine.Control,
    as: :start_exec

  defdelegate exec_inspect(exec_id, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :inspect_exec

  defdelegate exec_inspect(exec_id),
    to: TestcontainerEx.Engine.Control,
    as: :inspect_exec

  defdelegate exec_resize(exec_id, width, height, base_url),
    to: TestcontainerEx.Engine.Control,
    as: :resize_exec

  defdelegate exec_resize(exec_id, width, height),
    to: TestcontainerEx.Engine.Control,
    as: :resize_exec

  # ── Engine status (via Docker/Podman/Minikube/Colima API) ─────────

  defdelegate engine_status(engine),
    to: TestcontainerEx.Engine.Status,
    as: :status

  defdelegate engine_status(),
    to: TestcontainerEx.Engine.Status,
    as: :status

  defdelegate engine_reachable?(),
    to: TestcontainerEx.Engine.Status,
    as: :reachable?

  defdelegate colima_status(),
    to: TestcontainerEx.Engine.Status,
    as: :colima_status

  defdelegate minikube_status(),
    to: TestcontainerEx.Engine.Status,
    as: :minikube_status

  defdelegate engine_info(base_url),
    to: TestcontainerEx.Engine.Status,
    as: :engine_info

  defdelegate engine_info(),
    to: TestcontainerEx.Engine.Status,
    as: :engine_info

  defdelegate engine_version(base_url),
    to: TestcontainerEx.Engine.Status,
    as: :engine_version

  defdelegate engine_version(),
    to: TestcontainerEx.Engine.Status,
    as: :engine_version

  defdelegate list_containers(opts, base_url),
    to: TestcontainerEx.Engine.Status,
    as: :list_containers

  defdelegate list_containers(opts),
    to: TestcontainerEx.Engine.Status,
    as: :list_containers

  defdelegate list_containers(),
    to: TestcontainerEx.Engine.Status,
    as: :list_containers

  defdelegate list_images(opts, base_url),
    to: TestcontainerEx.Engine.Status,
    as: :list_images

  defdelegate list_images(opts),
    to: TestcontainerEx.Engine.Status,
    as: :list_images

  defdelegate list_images(),
    to: TestcontainerEx.Engine.Status,
    as: :list_images

  defdelegate list_networks(base_url),
    to: TestcontainerEx.Engine.Status,
    as: :list_networks

  defdelegate list_networks(),
    to: TestcontainerEx.Engine.Status,
    as: :list_networks

  defdelegate list_volumes(base_url),
    to: TestcontainerEx.Engine.Status,
    as: :list_volumes

  defdelegate list_volumes(),
    to: TestcontainerEx.Engine.Status,
    as: :list_volumes

  defdelegate disk_usage(base_url),
    to: TestcontainerEx.Engine.Status,
    as: :disk_usage

  defdelegate disk_usage(),
    to: TestcontainerEx.Engine.Status,
    as: :disk_usage

  defdelegate engine_ping(base_url),
    to: TestcontainerEx.Engine.Status,
    as: :ping

  defdelegate engine_ping(),
    to: TestcontainerEx.Engine.Status,
    as: :ping

  defdelegate engine_events(opts, base_url),
    to: TestcontainerEx.Engine.Status,
    as: :events

  defdelegate engine_events(opts),
    to: TestcontainerEx.Engine.Status,
    as: :events

  defdelegate engine_events(),
    to: TestcontainerEx.Engine.Status,
    as: :events

  # ── Debugging ─────────────────────────────────────────────────────

  defdelegate debug_status, to: TestcontainerEx.Debug, as: :status
  defdelegate debug_inspect(container), to: TestcontainerEx.Debug, as: :inspect_container
  defdelegate debug_summarize(container), to: TestcontainerEx.Debug, as: :summarize
  defdelegate debug_list_containers, to: TestcontainerEx.Debug, as: :list_containers
  defdelegate debug_list_networks, to: TestcontainerEx.Debug, as: :list_networks

  # ── DevTools (runtime container interaction) ──────────────────────

  defdelegate dev_exec(container, command, opts), to: TestcontainerEx.DevTools, as: :exec

  defdelegate dev_exec_lines(container, command, opts),
    to: TestcontainerEx.DevTools,
    as: :exec_lines

  defdelegate dev_copy_to(container, dest_path, source, opts),
    to: TestcontainerEx.DevTools,
    as: :copy_to

  defdelegate dev_write_file(container, dest_path, contents, opts),
    to: TestcontainerEx.DevTools,
    as: :write_file

  defdelegate dev_copy_from(container, container_path, host_path, opts),
    to: TestcontainerEx.DevTools,
    as: :copy_from

  defdelegate dev_read_file(container, container_path, opts),
    to: TestcontainerEx.DevTools,
    as: :read_file

  defdelegate dev_read_lines(container, container_path, opts),
    to: TestcontainerEx.DevTools,
    as: :read_lines

  defdelegate dev_delete_file(container, container_path, opts),
    to: TestcontainerEx.DevTools,
    as: :delete_file

  defdelegate dev_exists?(container, path, opts), to: TestcontainerEx.DevTools, as: :exists?

  defdelegate dev_list_dir(container, container_path, opts),
    to: TestcontainerEx.DevTools,
    as: :list_dir

  defdelegate dev_list_dir_long(container, container_path, opts),
    to: TestcontainerEx.DevTools,
    as: :list_dir_long

  defdelegate dev_processes(container, opts), to: TestcontainerEx.DevTools, as: :processes
  defdelegate dev_stats(container, opts), to: TestcontainerEx.DevTools, as: :stats
  defdelegate dev_state(container, opts), to: TestcontainerEx.DevTools, as: :state
  defdelegate dev_running?(container, opts), to: TestcontainerEx.DevTools, as: :running?

  defdelegate dev_kill_process(container, pid, opts),
    to: TestcontainerEx.DevTools,
    as: :kill_process

  defdelegate dev_kill_process_name(container, name, opts),
    to: TestcontainerEx.DevTools,
    as: :kill_process_name

  defdelegate dev_find_pids(container, name, opts), to: TestcontainerEx.DevTools, as: :find_pids

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
