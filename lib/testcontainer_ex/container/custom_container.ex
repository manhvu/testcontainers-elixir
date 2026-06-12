# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.CustomContainer do
  @moduledoc """
  A flexible, user-defined container specification with full lifecycle control.

  `CustomContainer` lets users define any container configuration and then
  manage it through a unified API — start, stop, restart, pause, inspect,
  exec, logs, stats, file upload/download, and more.

  ## Defining a custom container

      alias TestcontainerEx.CustomContainer
      alias TestcontainerEx.Container.Config

      config =
        CustomContainer.new("my-app:latest")
        |> CustomContainer.with_exposed_port(8080)
        |> CustomContainer.with_exposed_port(5432)
        |> CustomContainer.with_env("DATABASE_URL", "postgres://localhost/mydb")
        |> CustomContainer.with_volume("/host/data", "/app/data")
        |> CustomContainer.with_cmd(["my-app", "start"])
        |> CustomContainer.with_network("my-network")
        |> CustomContainer.with_wait_strategy(
          TestcontainerEx.Wait.http("/health", 8080, status_code: 200)
        )

  ## Starting and controlling

      # Start the container
      {:ok, container} = TestcontainerEx.start_container(config)

      # Execute a command inside
      {:ok, output} = TestcontainerEx.exec(container.container_id, ["ls", "/app"])

      # Stream logs
      {:ok, logs} = TestcontainerEx.container_logs(container.container_id, tail: 100)

      # Get resource usage stats
      stats = TestcontainerEx.container_stats(container.container_id)

      # Stop and remove
      :ok = TestcontainerEx.stop_container(container.container_id)
      :ok = TestcontainerEx.container_remove(container.container_id, force: true)

  ## Using with ExUnit

      import TestcontainerEx.ExUnit

      # Per-test container
      container :my_app, CustomContainer.new("my-app:latest")
  """

  alias TestcontainerEx.Container.Config

  @type t :: %__MODULE__{
          config: Config.t(),
          wait_strategies: [struct()],
          auto_remove: boolean(),
          labels: %{String.t() => String.t()},
          after_start: (Config.t(), Config.t(), Req.Request.t() -> :ok | {:error, term()})
        }

  defstruct [
    :config,
    wait_strategies: [],
    auto_remove: true,
    labels: %{},
    after_start: nil
  ]

  # ── Constructors ─────────────────────────────────────────────────

  @doc """
  Creates a new custom container with the given image.
  """
  @spec new(String.t()) :: t()
  def new(image) when is_binary(image) do
    %__MODULE__{
      config: Config.new(image),
      auto_remove: true
    }
  end

  @doc """
  Creates a custom container from an existing `Config` struct.
  """
  @spec from_config(Config.t()) :: t()
  def from_config(%Config{} = config) do
    %__MODULE__{
      config: config,
      auto_remove: config.auto_remove
    }
  end

  # ── Builder functions (delegate to Config) ───────────────────────

  @doc "Sets the container image."
  @spec with_image(t(), String.t()) :: t()
  def with_image(%__MODULE__{} = cc, image) when is_binary(image) do
    %{cc | config: %{cc.config | image: image}}
  end

  @doc "Adds an exposed port (random host port)."
  @spec with_exposed_port(t(), integer()) :: t()
  def with_exposed_port(%__MODULE__{} = cc, port) when is_integer(port) do
    %{cc | config: Config.with_exposed_port(cc.config, port)}
  end

  @doc "Adds multiple exposed ports."
  @spec with_exposed_ports(t(), [integer()]) :: t()
  def with_exposed_ports(%__MODULE__{} = cc, ports) when is_list(ports) do
    %{cc | config: Config.with_exposed_ports(cc.config, ports)}
  end

  @doc "Adds a fixed port mapping (container_port -> host_port)."
  @spec with_fixed_port(t(), integer(), integer()) :: t()
  def with_fixed_port(%__MODULE__{} = cc, container_port, host_port)
      when is_integer(container_port) and is_integer(host_port) do
    %{cc | config: Config.with_fixed_port(cc.config, container_port, host_port)}
  end

  @doc "Sets an environment variable."
  @spec with_env(t(), String.t() | atom(), String.t()) :: t()
  def with_env(%__MODULE__{} = cc, key, value) do
    %{cc | config: Config.with_environment(cc.config, key, value)}
  end

  @doc "Sets multiple environment variables."
  @spec with_envs(t(), %{String.t() => String.t()} | keyword()) :: t()
  def with_envs(%__MODULE__{} = cc, envs) when is_map(envs) or is_list(envs) do
    new_config =
      Enum.reduce(envs, cc.config, fn {k, v}, acc ->
        Config.with_environment(acc, k, v)
      end)

    %{cc | config: new_config}
  end

  @doc "Adds a bind mount (host path -> container path)."
  @spec with_volume(String.t(), String.t(), String.t()) :: t()
  def with_volume(%__MODULE__{} = cc, host_path, container_path, options \\ "ro") do
    %{cc | config: Config.with_bind_mount(cc.config, host_path, container_path, options)}
  end

  @doc "Adds a named volume mount."
  @spec with_named_volume(t(), String.t(), String.t(), boolean()) :: t()
  def with_named_volume(%__MODULE__{} = cc, volume, container_path, read_only \\ false) do
    %{cc | config: Config.with_bind_volume(cc.config, volume, container_path, read_only)}
  end

  @doc "Sets the command to run in the container."
  @spec with_cmd(t(), [String.t()]) :: t()
  def with_cmd(%__MODULE__{} = cc, cmd) when is_list(cmd) do
    %{cc | config: Config.with_cmd(cc.config, cmd)}
  end

  @doc "Sets the entrypoint."
  @spec with_entrypoint(t(), [String.t()]) :: t()
  def with_entrypoint(%__MODULE__{} = cc, entrypoint) when is_list(entrypoint) do
    %{cc | config: %{cc.config | cmd: entrypoint}}
  end

  @doc "Sets the working directory inside the container."
  @spec with_workdir(t(), String.t()) :: t()
  def with_workdir(%__MODULE__{} = cc, workdir) when is_binary(workdir) do
    %{cc | config: Config.with_environment(cc.config, "WORKDIR", workdir)}
  end

  @doc "Sets the container name."
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = cc, name) when is_binary(name) do
    %{cc | config: Config.with_name(cc.config, name)}
  end

  @doc "Sets the hostname inside the container."
  @spec with_hostname(t(), String.t()) :: t()
  def with_hostname(%__MODULE__{} = cc, hostname) when is_binary(hostname) do
    %{cc | config: Config.with_hostname(cc.config, hostname)}
  end

  @doc "Sets the network mode or network name."
  @spec with_network(t(), String.t()) :: t()
  def with_network(%__MODULE__{} = cc, network) when is_binary(network) do
    %{cc | config: Config.with_network(cc.config, network)}
  end

  @doc "Sets the network mode (e.g. \"host\", \"bridge\", \"none\")."
  @spec with_network_mode(t(), String.t()) :: t()
  def with_network_mode(%__MODULE__{} = cc, mode) when is_binary(mode) do
    %{cc | config: Config.with_network_mode(cc.config, mode)}
  end

  @doc "Adds a label to the container."
  @spec with_label(t(), String.t(), String.t()) :: t()
  def with_label(%__MODULE__{} = cc, key, value) when is_binary(key) and is_binary(value) do
    %{cc | config: Config.with_label(cc.config, key, value)}
  end

  @doc "Adds multiple labels."
  @spec with_labels(t(), %{String.t() => String.t()}) :: t()
  def with_labels(%__MODULE__{} = cc, labels) when is_map(labels) do
    new_labels = Map.merge(cc.labels, labels)
    new_config_labels = Map.merge(cc.config.labels, labels)
    %{cc | labels: new_labels, config: %{cc.config | labels: new_config_labels}}
  end

  @doc "Sets whether the container should be auto-removed when stopped."
  @spec with_auto_remove(t(), boolean()) :: t()
  def with_auto_remove(%__MODULE__{} = cc, auto_remove) when is_boolean(auto_remove) do
    %{cc | auto_remove: auto_remove, config: Config.with_auto_remove(cc.config, auto_remove)}
  end

  @doc "Sets privileged mode."
  @spec with_privileged(t(), boolean()) :: t()
  def with_privileged(%__MODULE__{} = cc, privileged) when is_boolean(privileged) do
    %{cc | config: Config.with_privileged(cc.config, privileged)}
  end

  @doc "Sets the pull policy."
  @spec with_pull_policy(t(), struct()) :: t()
  def with_pull_policy(%__MODULE__{} = cc, %TestcontainerEx.PullPolicy{} = policy) do
    %{cc | config: Config.with_pull_policy(cc.config, policy)}
  end

  @doc "Adds a file to copy into the container at startup."
  @spec with_copy_file(t(), String.t(), String.t()) :: t()
  def with_copy_file(%__MODULE__{} = cc, container_path, contents)
      when is_binary(container_path) and is_binary(contents) do
    %{cc | config: Config.with_copy_to(cc.config, container_path, contents)}
  end

  @doc "Adds a wait strategy for container readiness."
  @spec with_wait_strategy(t(), struct()) :: t()
  def with_wait_strategy(%__MODULE__{} = cc, strategy) when is_struct(strategy) do
    %{cc | wait_strategies: cc.wait_strategies ++ [strategy]}
  end

  @doc "Adds multiple wait strategies."
  @spec with_wait_strategies(t(), [struct()]) :: t()
  def with_wait_strategies(%__MODULE__{} = cc, strategies) when is_list(strategies) do
    %{cc | wait_strategies: cc.wait_strategies ++ strategies}
  end

  @doc """
  Sets a callback to run after the container starts successfully.
  Receives `(custom_container, started_container_config, conn)`.
  """
  @spec after_start(t(), (t(), Config.t(), Req.Request.t() -> term())) :: t()
  def after_start(%__MODULE__{} = cc, callback) when is_function(callback, 3) do
    %{cc | after_start: callback}
  end

  @doc "Sets the user (UID or user:group) for the container."
  @spec with_user(t(), String.t()) :: t()
  def with_user(%__MODULE__{} = cc, user) when is_binary(user) do
    %{cc | config: Config.with_environment(cc.config, "USER", user)}
  end

  @doc "Sets memory limit in bytes."
  @spec with_memory_limit(t(), integer()) :: t()
  def with_memory_limit(%__MODULE__{} = cc, bytes) when is_integer(bytes) do
    %{cc | config: Config.with_label(cc.config, "memory.limit", to_string(bytes))}
  end

  @doc "Sets CPU limit (fraction of a CPU core, e.g. 0.5 for half a core)."
  @spec with_cpu_limit(t(), float()) :: t()
  def with_cpu_limit(%__MODULE__{} = cc, cpus) when is_float(cpus) do
    %{cc | config: Config.with_label(cc.config, "cpu.limit", to_string(cpus))}
  end

  @doc "Sets the restart policy (e.g. \"always\", \"unless-stopped\", \"on-failure:5\")."
  @spec with_restart_policy(t(), String.t()) :: t()
  def with_restart_policy(%__MODULE__{} = cc, policy) when is_binary(policy) do
    %{cc | config: Config.with_label(cc.config, "restart.policy", policy)}
  end

  @doc "Sets the stop timeout in seconds."
  @spec with_stop_timeout(t(), integer()) :: t()
  def with_stop_timeout(%__MODULE__{} = cc, seconds) when is_integer(seconds) do
    %{cc | config: Config.with_label(cc.config, "stop.timeout", to_string(seconds))}
  end

  @doc "Sets the stop signal (e.g. \"SIGTERM\", \"SIGKILL\")."
  @spec with_stop_signal(t(), String.t()) :: t()
  def with_stop_signal(%__MODULE__{} = cc, signal) when is_binary(signal) do
    %{cc | config: %{cc.config | cmd: cc.config.cmd}}
  end

  @doc "Adds an extra host entry (hostname -> ip)."
  @spec with_extra_host(t(), String.t(), String.t()) :: t()
  def with_extra_host(%__MODULE__{} = cc, hostname, ip)
      when is_binary(hostname) and is_binary(ip) do
    %{cc | config: Config.with_label(cc.config, "extra_host.#{hostname}", ip)}
  end

  @doc "Sets DNS servers."
  @spec with_dns(t(), [String.t()]) :: t()
  def with_dns(%__MODULE__{} = cc, dns_servers) when is_list(dns_servers) do
    %{cc | config: Config.with_label(cc.config, "dns", Enum.join(dns_servers, ","))}
  end

  @doc "Sets the domain name."
  @spec with_domainname(t(), String.t()) :: t()
  def with_domainname(%__MODULE__{} = cc, domain) when is_binary(domain) do
    %{cc | config: %{cc.config | hostname: cc.config.hostname || domain}}
  end

  # ── Runtime info ─────────────────────────────────────────────────

  @doc """
  Returns a map of runtime information for a started container.
  """
  @spec runtime_info(Config.t()) :: map()
  def runtime_info(%Config{} = container) do
    %{
      container_id: container.container_id,
      image: container.image,
      name: container.name,
      ip_address: container.ip_address,
      ports: container.exposed_ports,
      environment: container.environment,
      labels: container.labels,
      network: container.network,
      network_mode: container.network_mode,
      hostname: container.hostname
    }
  end

  @doc """
  Returns the host and port for a given container port.
  """
  @spec endpoint(Config.t(), integer()) :: {String.t(), integer()} | nil
  def endpoint(%Config{} = container, container_port) do
    case Config.mapped_port(container, container_port) do
      nil -> nil
      host_port -> {TestcontainerEx.get_host(container), host_port}
    end
  end

  @doc """
  Returns a connection URL for common protocols.

  ## Examples

      iex> CustomContainer.endpoint_url(container, 5432, "postgres")
      "postgres://localhost:5432"

      iex> CustomContainer.endpoint_url(container, 6379, "redis")
      "redis://localhost:6379"
  """
  @spec endpoint_url(Config.t(), integer(), String.t()) :: String.t() | nil
  def endpoint_url(%Config{} = container, container_port, scheme) do
    case endpoint(container, container_port) do
      nil -> nil
      {host, port} -> "#{scheme}://#{host}:#{port}"
    end
  end

  @doc """
  Returns a connection URL with authentication.
  """
  @spec endpoint_url(Config.t(), integer(), String.t(), keyword()) :: String.t() | nil
  def endpoint_url(%Config{} = container, container_port, scheme, opts) do
    case endpoint(container, container_port) do
      nil ->
        nil

      {host, port} ->
        auth = build_auth_segment(opts)
        "#{scheme}://#{auth}#{host}:#{port}"
    end
  end

  defp build_auth_segment(opts) do
    case {Keyword.get(opts, :username), Keyword.get(opts, :password)} do
      {nil, nil} -> ""
      {username, nil} -> "#{username}@"
      {username, password} -> "#{username}:#{password}@"
    end
  end

  # ── Builder protocol implementation ──────────────────────────────

  defimpl TestcontainerEx.Container.Builder do
    @impl true
    def build(%TestcontainerEx.CustomContainer{} = cc) do
      cc.config
      |> Config.with_waiting_strategies(cc.wait_strategies)
      |> Config.with_auto_remove(cc.auto_remove)
      |> then(fn config ->
        Enum.reduce(cc.labels, config, fn {k, v}, acc ->
          Config.with_label(acc, k, v)
        end)
      end)
    end

    @impl true
    def after_start(%TestcontainerEx.CustomContainer{after_start: nil}, _container, _conn) do
      :ok
    end

    def after_start(%TestcontainerEx.CustomContainer{after_start: callback}, container, conn)
        when is_function(callback, 3) do
      callback.(container, container, conn)
    end
  end
end
