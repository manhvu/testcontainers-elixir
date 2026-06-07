defmodule TestcontainerEx.Container.Config do
  @moduledoc """
  Container configuration struct and builder functions.

  This module is pure data — no side effects, no Docker API calls.
  Use `TestcontainerEx.Container.Builder` for protocol-based build pipelines.
  """

  require Logger

  @type t :: %__MODULE__{}

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
    pull_policy: nil
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

  @spec valid_image(t()) :: {:ok, t()} | {:error, String.t()}
  def valid_image(%__MODULE__{image: image, check_image: check_image} = config) do
    if Regex.match?(check_image || ~r/.*/, image) do
      {:ok, config}
    else
      {:error,
       "Unexpected image #{image}. If this is a valid image, provide a broader `check_image` regex to the container configuration."}
    end
  end

  @spec valid_image!(t()) :: t()
  def valid_image!(%__MODULE__{} = config) do
    case valid_image(config) do
      {:ok, config} -> config
      {:error, message} -> raise ArgumentError, message: message
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

  def inspect(config, opts) do
    port_info =
      Enum.map_join(config.exposed_ports, ", ", fn
        {p, nil} -> "#{p}->auto"
        {p, h} -> "#{p}->#{h}"
      end)

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
