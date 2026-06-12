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
    to: TestcontainerEx.Docker.Control,
    as: :start

  defdelegate container_start(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :start

  defdelegate container_stop(container_id, timeout, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :stop

  defdelegate container_stop(container_id, timeout),
    to: TestcontainerEx.Docker.Control,
    as: :stop

  defdelegate container_stop(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :stop

  defdelegate container_restart(container_id, timeout, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :restart

  defdelegate container_restart(container_id, timeout),
    to: TestcontainerEx.Docker.Control,
    as: :restart

  defdelegate container_restart(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :restart

  defdelegate container_kill(container_id, signal, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :kill

  defdelegate container_kill(container_id, signal),
    to: TestcontainerEx.Docker.Control,
    as: :kill

  defdelegate container_kill(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :kill

  defdelegate container_pause(container_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :pause

  defdelegate container_pause(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :pause

  defdelegate container_unpause(container_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :unpause

  defdelegate container_unpause(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :unpause

  defdelegate container_remove(container_id, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :remove

  defdelegate container_remove(container_id, opts),
    to: TestcontainerEx.Docker.Control,
    as: :remove

  defdelegate container_remove(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :remove

  defdelegate container_rename(container_id, new_name, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :rename

  defdelegate container_rename(container_id, new_name),
    to: TestcontainerEx.Docker.Control,
    as: :rename

  defdelegate container_update(container_id, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :update

  defdelegate container_update(container_id, opts),
    to: TestcontainerEx.Docker.Control,
    as: :update

  defdelegate container_inspect(container_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :inspect_container

  defdelegate container_inspect(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :inspect_container

  defdelegate container_state(container_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :state

  defdelegate container_state(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :state

  defdelegate container_running?(container_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :running?

  defdelegate container_running?(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :running?

  defdelegate container_wait(container_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :wait

  defdelegate container_wait(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :wait

  defdelegate container_stats(container_id, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :stats

  defdelegate container_stats(container_id, opts),
    to: TestcontainerEx.Docker.Control,
    as: :stats

  defdelegate container_stats(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :stats

  defdelegate container_top(container_id, ps_args, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :top

  defdelegate container_top(container_id, ps_args),
    to: TestcontainerEx.Docker.Control,
    as: :top

  defdelegate container_top(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :top

  defdelegate container_upload(container_id, path, source, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :upload

  defdelegate container_upload(container_id, path, source),
    to: TestcontainerEx.Docker.Control,
    as: :upload

  defdelegate container_download(container_id, path, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :download

  defdelegate container_download(container_id, path),
    to: TestcontainerEx.Docker.Control,
    as: :download

  defdelegate container_download_file(container_id, path, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :download_file

  defdelegate container_download_file(container_id, path),
    to: TestcontainerEx.Docker.Control,
    as: :download_file

  defdelegate container_commit(container_id, repo_tag, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :commit

  defdelegate container_commit(container_id, repo_tag, opts),
    to: TestcontainerEx.Docker.Control,
    as: :commit

  defdelegate container_commit(container_id, repo_tag),
    to: TestcontainerEx.Docker.Control,
    as: :commit

  defdelegate container_export(container_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :export

  defdelegate container_export(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :export

  defdelegate container_resize(container_id, width, height, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :resize

  defdelegate container_resize(container_id, width, height),
    to: TestcontainerEx.Docker.Control,
    as: :resize

  defdelegate container_attach(container_id, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :attach

  defdelegate container_attach(container_id, opts),
    to: TestcontainerEx.Docker.Control,
    as: :attach

  defdelegate container_attach(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :attach

  defdelegate container_create(config, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :create

  defdelegate container_create(config),
    to: TestcontainerEx.Docker.Control,
    as: :create

  defdelegate container_create_named(name, config, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :create_named

  defdelegate container_create_named(name, config),
    to: TestcontainerEx.Docker.Control,
    as: :create_named

  defdelegate container_logs_raw(container_id, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :logs

  defdelegate container_logs_raw(container_id, opts),
    to: TestcontainerEx.Docker.Control,
    as: :logs

  defdelegate container_logs_raw(container_id),
    to: TestcontainerEx.Docker.Control,
    as: :logs

  defdelegate exec_create(container_id, command, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :create_exec

  defdelegate exec_create(container_id, command, opts),
    to: TestcontainerEx.Docker.Control,
    as: :create_exec

  defdelegate exec_create(container_id, command),
    to: TestcontainerEx.Docker.Control,
    as: :create_exec

  defdelegate exec_start(exec_id, opts, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :start_exec

  defdelegate exec_start(exec_id, opts),
    to: TestcontainerEx.Docker.Control,
    as: :start_exec

  defdelegate exec_start(exec_id),
    to: TestcontainerEx.Docker.Control,
    as: :start_exec

  defdelegate exec_inspect(exec_id, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :inspect_exec

  defdelegate exec_inspect(exec_id),
    to: TestcontainerEx.Docker.Control,
    as: :inspect_exec

  defdelegate exec_resize(exec_id, width, height, base_url),
    to: TestcontainerEx.Docker.Control,
    as: :resize_exec

  defdelegate exec_resize(exec_id, width, height),
    to: TestcontainerEx.Docker.Control,
    as: :resize_exec

  # ── Engine status (via Docker/Podman/Minikube/Colima API) ─────────

  defdelegate engine_status(engine),
    to: TestcontainerEx.Docker.Status,
    as: :status

  defdelegate engine_status(),
    to: TestcontainerEx.Docker.Status,
    as: :status

  defdelegate engine_reachable?(),
    to: TestcontainerEx.Docker.Status,
    as: :reachable?

  defdelegate colima_status(),
    to: TestcontainerEx.Docker.Status,
    as: :colima_status

  defdelegate minikube_status(),
    to: TestcontainerEx.Docker.Status,
    as: :minikube_status

  defdelegate engine_info(base_url),
    to: TestcontainerEx.Docker.Status,
    as: :engine_info

  defdelegate engine_info(),
    to: TestcontainerEx.Docker.Status,
    as: :engine_info

  defdelegate engine_version(base_url),
    to: TestcontainerEx.Docker.Status,
    as: :engine_version

  defdelegate engine_version(),
    to: TestcontainerEx.Docker.Status,
    as: :engine_version

  defdelegate list_containers(opts, base_url),
    to: TestcontainerEx.Docker.Status,
    as: :list_containers

  defdelegate list_containers(opts),
    to: TestcontainerEx.Docker.Status,
    as: :list_containers

  defdelegate list_containers(),
    to: TestcontainerEx.Docker.Status,
    as: :list_containers

  defdelegate list_images(opts, base_url),
    to: TestcontainerEx.Docker.Status,
    as: :list_images

  defdelegate list_images(opts),
    to: TestcontainerEx.Docker.Status,
    as: :list_images

  defdelegate list_images(),
    to: TestcontainerEx.Docker.Status,
    as: :list_images

  defdelegate list_networks(base_url),
    to: TestcontainerEx.Docker.Status,
    as: :list_networks

  defdelegate list_networks(),
    to: TestcontainerEx.Docker.Status,
    as: :list_networks

  defdelegate list_volumes(base_url),
    to: TestcontainerEx.Docker.Status,
    as: :list_volumes

  defdelegate list_volumes(),
    to: TestcontainerEx.Docker.Status,
    as: :list_volumes

  defdelegate disk_usage(base_url),
    to: TestcontainerEx.Docker.Status,
    as: :disk_usage

  defdelegate disk_usage(),
    to: TestcontainerEx.Docker.Status,
    as: :disk_usage

  defdelegate engine_ping(base_url),
    to: TestcontainerEx.Docker.Status,
    as: :ping

  defdelegate engine_ping(),
    to: TestcontainerEx.Docker.Status,
    as: :ping

  defdelegate engine_events(opts, base_url),
    to: TestcontainerEx.Docker.Status,
    as: :events

  defdelegate engine_events(opts),
    to: TestcontainerEx.Docker.Status,
    as: :events

  defdelegate engine_events(),
    to: TestcontainerEx.Docker.Status,
    as: :events

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
