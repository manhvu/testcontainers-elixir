defmodule TestcontainerEx.Container.Config do
  @moduledoc """
  Container configuration struct and builder functions.

  This module is pure data — no side effects, no Docker API calls.
  Use `TestcontainerEx.Container.Builder` for protocol-based build pipelines.
  """

  require Logger

  @typedoc """
  Container configuration.

  Fields:

  - `:image` — Docker image reference (e.g. `"postgres:15-alpine"`).
  - `:cmd` — override the image's default command.
  - `:environment` — map of environment variables.
  - `:auth` — optional Base64-encoded auth token for private registries.
  - `:exposed_ports` — list of `{container_port, host_port | nil}` tuples.
  - `:ip_address` — resolved IP address of the running container.
  - `:wait_strategies` — list of strategies determining when the container is ready.
  - `:privileged` — run the container in privileged mode.
  - `:bind_mounts` — list of bind mount specifications.
  - `:bind_volumes` — list of named volume mount specifications.
  - `:copy_to` — list of files to copy into the container at startup.
  - `:labels` — map of Docker labels to attach to the container.
  - `:auto_remove` — automatically remove the container when it stops.
  - `:container_id` — ID of the running container (set after start).
  - `:check_image` — optional regex to validate the image name.
  - `:network_mode` — Docker network mode (e.g. `"host"`, `"bridge"`).
  - `:network` — network name to connect the container to.
  - `:hostname` — container hostname.
  - `:name` — optional stable container name.
  - `:reuse` — when `true`, an existing container with the same config may be reused.
  - `:force_reuse` — force reuse even if the container is stale.
  - `:pull_policy` — controls when the image is pulled; see `TestcontainerEx.PullPolicy`.
  - `:log_consumer` — optional Logger level to stream container logs to (`:debug`, `:info`, etc.).
  - `:request_id` — correlation ID for tracing a `start_container` call.
  """
  @type t :: %__MODULE__{
          image: String.t(),
          cmd: [String.t()] | nil,
          environment: %{(atom() | String.t()) => String.t()},
          auth: String.t() | nil,
          exposed_ports: [{integer(), integer() | nil}],
          ip_address: String.t() | nil,
          wait_strategies: [struct()],
          privileged: boolean(),
          bind_mounts: [map()],
          bind_volumes: [map()],
          copy_to: [map()],
          labels: %{String.t() => String.t()},
          auto_remove: boolean(),
          container_id: String.t() | nil,
          check_image: Regex.t() | nil,
          network_mode: String.t() | nil,
          network: String.t() | nil,
          hostname: String.t() | nil,
          name: String.t() | nil,
          reuse: boolean(),
          force_reuse: boolean(),
          pull_policy: TestcontainerEx.PullPolicy.t() | nil,
          log_consumer: Logger.level() | nil,
          request_id: String.t() | nil
        }

  @enforce_keys [:image]
  defstruct [
    :image,
    cmd: nil,
    environment: %{},
    auth: nil,
    exposed_ports: [],
    ip_address: nil,
    wait_strategies: [],
    privileged: false,
    bind_mounts: [],
    bind_volumes: [],
    copy_to: [],
    labels: %{},
    auto_remove: false,
    container_id: nil,
    check_image: nil,
    network_mode: nil,
    network: nil,
    hostname: nil,
    name: nil,
    reuse: false,
    force_reuse: false,
    pull_policy: nil,
    log_consumer: nil,
    request_id: nil
  ]

  # ── Guards ────────────────────────────────────────────────────────

  defguard is_valid_image(check_image)
           when is_binary(check_image) or is_struct(check_image, Regex)

  @os_type (case :os.type() do
              {:win32, _} -> :windows
              {:unix, :darwin} -> :macos
              {:unix, _} -> :linux
            end)

  defguard is_os(name) when is_atom(name) and name == @os_type

  @spec os_type() :: :linux | :macos | :windows | :unknown
  def os_type do
    cond do
      is_os(:linux) -> :linux
      is_os(:macos) -> :macos
      is_os(:windows) -> :windows
      true -> :unknown
    end
  end

  # ── Constructors ─────────────────────────────────────────────────

  @spec new(String.t()) :: t()
  def new(image) when is_binary(image), do: %__MODULE__{image: image}

  # ── Builder functions ────────────────────────────────────────────

  @spec with_waiting_strategy(t(), struct()) :: t()
  def with_waiting_strategy(%__MODULE__{} = config, wait_fn) when is_struct(wait_fn) do
    %__MODULE__{config | wait_strategies: [wait_fn | config.wait_strategies]}
  end

  @spec with_waiting_strategies(t(), [struct()]) :: t()
  def with_waiting_strategies(%__MODULE__{} = config, wait_fns) when is_list(wait_fns) do
    Enum.reduce(wait_fns, config, fn fun, cfg -> with_waiting_strategy(cfg, fun) end)
  end

  @spec with_environment(t(), atom() | String.t(), String.t()) :: t()
  def with_environment(%__MODULE__{} = config, key, value)
      when (is_binary(key) or is_atom(key)) and is_binary(value) do
    %__MODULE__{config | environment: Map.put(config.environment, key, value)}
  end

  @spec with_exposed_port(t(), integer()) :: t()
  def with_exposed_port(%__MODULE__{} = config, port) when is_integer(port) do
    filtered =
      Enum.reject(config.exposed_ports, fn
        {p, _} -> p == port
        p -> p == port
      end)

    %__MODULE__{config | exposed_ports: [{port, nil} | filtered]}
  end

  @spec with_exposed_ports(t(), [integer()]) :: t()
  def with_exposed_ports(%__MODULE__{} = config, ports) when is_list(ports) do
    filtered =
      Enum.reject(config.exposed_ports, fn
        {p, _} -> p in ports
        p -> p in ports
      end)

    new_ports = Enum.map(ports, &{&1, nil})
    %__MODULE__{config | exposed_ports: new_ports ++ filtered}
  end

  @spec with_fixed_port(t(), integer(), integer() | nil) :: t()
  def with_fixed_port(%__MODULE__{} = config, port, host_port \\ nil)
      when is_integer(port) and (is_nil(host_port) or is_integer(host_port)) do
    filtered =
      Enum.reject(config.exposed_ports, fn
        {p, _} -> p == port
        p -> p == port
      end)

    %__MODULE__{config | exposed_ports: [{port, host_port || port} | filtered]}
  end

  @spec with_bind_mount(t(), String.t(), String.t(), String.t()) :: t()
  def with_bind_mount(%__MODULE__{} = config, host_src, container_dest, options \\ "ro")
      when is_binary(host_src) and is_binary(container_dest) and is_binary(options) do
    mount = %{host_src: host_src, container_dest: container_dest, options: options}
    %__MODULE__{config | bind_mounts: [mount | config.bind_mounts]}
  end

  @spec with_bind_volume(t(), String.t(), String.t(), boolean()) :: t()
  def with_bind_volume(%__MODULE__{} = config, volume, container_dest, read_only \\ false)
      when is_binary(volume) and is_binary(container_dest) and is_boolean(read_only) do
    vol = %{volume: volume, container_dest: container_dest, read_only: read_only}
    %__MODULE__{config | bind_volumes: [vol | config.bind_volumes]}
  end

  @spec with_label(t(), String.t(), String.t()) :: t()
  def with_label(%__MODULE__{} = config, key, value) when is_binary(key) and is_binary(value) do
    %__MODULE__{config | labels: Map.put(config.labels, key, value)}
  end

  @spec with_cmd(t(), [String.t()]) :: t()
  def with_cmd(%__MODULE__{} = config, cmd) when is_list(cmd) do
    %__MODULE__{config | cmd: cmd}
  end

  @spec with_auto_remove(t(), boolean()) :: t()
  def with_auto_remove(%__MODULE__{} = config, auto_remove) when is_boolean(auto_remove) do
    %__MODULE__{config | auto_remove: auto_remove}
  end

  @spec with_privileged(t(), boolean()) :: t()
  def with_privileged(%__MODULE__{} = config, privileged) when is_boolean(privileged) do
    %__MODULE__{config | privileged: privileged}
  end

  @spec with_reuse(t(), boolean()) :: t()
  def with_reuse(%__MODULE__{} = config, reuse) when is_boolean(reuse) do
    if config.auto_remove,
      do: raise(ArgumentError, "Cannot reuse a container that is set to auto-remove")

    %__MODULE__{config | reuse: reuse}
  end

  @spec with_force_reuse(t(), boolean()) :: t()
  def with_force_reuse(%__MODULE__{} = config, force_reuse) when is_boolean(force_reuse) do
    if config.auto_remove,
      do: raise(ArgumentError, "Cannot reuse a container that is set to auto-remove")

    %__MODULE__{config | reuse: true, force_reuse: force_reuse}
  end

  @spec with_auth(t(), String.t(), String.t()) :: t()
  def with_auth(%__MODULE__{} = config, username, password)
      when is_binary(username) and is_binary(password) do
    token =
      Jason.encode!(%{username: username, password: password})
      |> Base.encode64()

    %__MODULE__{config | auth: token}
  end

  @spec with_check_image(t(), String.t() | Regex.t()) :: t()
  def with_check_image(%__MODULE__{} = config, check_image) when is_binary(check_image) do
    regex = Regex.compile!(check_image)
    with_check_image(config, regex)
  end

  def with_check_image(%__MODULE__{} = config, %Regex{} = check_image) do
    %__MODULE__{config | check_image: check_image}
  end

  @spec with_network_mode(t(), String.t()) :: t()
  def with_network_mode(%__MODULE__{} = config, mode) when is_binary(mode) do
    mode = String.downcase(mode)

    if mode == "host" and not is_os(:linux) do
      Logger.warning(
        "To use host network mode on non-linux hosts, please see https://docs.docker.com/network/drivers/host"
      )
    end

    %__MODULE__{config | network_mode: mode}
  end

  @spec with_network(t(), String.t()) :: t()
  def with_network(%__MODULE__{} = config, network_name) when is_binary(network_name) do
    %__MODULE__{config | network: network_name}
  end

  @spec with_hostname(t(), String.t()) :: t()
  def with_hostname(%__MODULE__{} = config, hostname) when is_binary(hostname) do
    %__MODULE__{config | hostname: hostname}
  end

  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  @spec with_copy_to(t(), String.t(), String.t()) :: t()
  def with_copy_to(%__MODULE__{} = config, target, source)
      when is_binary(target) and is_binary(source) do
    %__MODULE__{config | copy_to: [%{"target" => target, "contents" => source} | config.copy_to]}
  end

  @spec with_pull_policy(t(), struct()) :: t()
  def with_pull_policy(%__MODULE__{} = config, %TestcontainerEx.PullPolicy{} = policy) do
    %__MODULE__{config | pull_policy: policy}
  end

  # ── Query functions ──────────────────────────────────────────────

  @spec mapped_port(t(), integer()) :: integer() | nil
  def mapped_port(%__MODULE__{} = container, port) when is_number(port) do
    Enum.find_value(container.exposed_ports, nil, fn
      {^port, host_port} -> host_port
      _ -> nil
    end)
  end

  @doc """
  Sets the log consumer level for streaming container logs to Logger.

  When set, container stdout/stderr will be piped through `Logger` at the
  specified level after the container starts.
  """
  @spec with_log_consumer(t(), Logger.level()) :: t()
  def with_log_consumer(%__MODULE__{} = config, level) when is_atom(level) do
    %__MODULE__{config | log_consumer: level}
  end

  @doc """
  Sets a correlation / request ID for tracing this container start.

  If not set, one will be generated automatically by `start_container/1`.
  """
  @spec with_request_id(t(), String.t()) :: t()
  def with_request_id(%__MODULE__{} = config, request_id) when is_binary(request_id) do
    %__MODULE__{config | request_id: request_id}
  end

  @spec valid_image(t()) :: {:ok, t()} | {:error, TestcontainerEx.Error.t()}
  def valid_image(%__MODULE__{image: image, check_image: check_image} = config) do
    if Regex.match?(check_image || ~r/.*/, image) do
      {:ok, config}
    else
      {:error,
       %TestcontainerEx.Error{
         code: :image_not_found,
         message:
           "Unexpected image #{image}. If this is a valid image, provide a broader `check_image` regex to the container configuration.",
         context: %{image: image}
       }}
    end
  end

  @spec valid_image!(t()) :: t()
  def valid_image!(%__MODULE__{} = config) do
    case valid_image(config) do
      {:ok, config} -> config
      {:error, %TestcontainerEx.Error{} = error} -> raise ArgumentError, message: error.message
    end
  end

  # ── Container environment detection ──────────────────────────────

  @doc """
  Returns `true` when running inside a container (Docker, Podman, Kubernetes).

  Accepts optional overrides for the `.dockerenv` path, cgroup path,
  Kubernetes secrets path, and Podman containerenv path.
  """
  @spec running_in_container?(String.t(), String.t(), String.t(), String.t()) :: boolean()
  def running_in_container?(
        dockerenv_path \\ "/.dockerenv",
        cgroup_path \\ "/proc/1/cgroup",
        k8s_secrets_path \\ "/var/run/secrets/kubernetes.io",
        containerenv_path \\ "/.containerenv"
      ) do
    cond do
      File.exists?(dockerenv_path) ->
        true

      File.exists?(k8s_secrets_path) ->
        true

      File.exists?(containerenv_path) ->
        true

      true ->
        case File.read(cgroup_path) do
          {:ok, content} ->
            Regex.match?(~r/(docker|kubepods|lxc|containerd|podman)/, content)

          {:error, _} ->
            false
        end
    end
  end

  @doc """
  Formats a list of exposed ports into a human-readable string.

  ## Examples

      iex> format_ports([{8080, 32768}, {9090, nil}])
      "8080->32768, 9090->auto"
  """
  @spec format_ports([{integer() | String.t(), integer() | nil}]) :: String.t()
  def format_ports(exposed_ports) do
    Enum.map_join(exposed_ports, ", ", fn
      {p, nil} -> "#{p}->auto"
      {p, h} -> "#{p}->#{h}"
    end)
  end
end

# Builder protocol implementation for Config (identity — already built)
defimpl TestcontainerEx.Container.Builder, for: TestcontainerEx.Container.Config do
  @impl true
  def build(config), do: config

  @impl true
  def after_start(_config, _container, _conn), do: :ok
end

defimpl Inspect, for: TestcontainerEx.Container.Config do
  import Inspect.Algebra
  alias TestcontainerEx.Container.Config

  def inspect(config, opts) do
    port_info = Config.format_ports(config.exposed_ports)

    fields = [
      image: config.image,
      container_id: config.container_id,
      ports: port_info,
      ip_address: config.ip_address,
      network: config.network,
      reuse: config.reuse
    ]

    concat(["#Container<", to_doc(fields, opts), ">"])
  end
end
