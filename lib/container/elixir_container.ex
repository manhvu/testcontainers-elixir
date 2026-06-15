# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.ElixirContainer do
  @moduledoc """
  Provides functionality for creating and managing Elixir/Erlang container
  configurations — useful for testing distributed Erlang, remote deployment,
  clustering, and running Elixir releases inside containers.

  ## Basic usage

      {:ok, container} = TestcontainerEx.start_container(ElixirContainer.new())

  ## With a specific Elixir version

      config =
        ElixirContainer.new()
        |> ElixirContainer.with_image("elixir:1.17-otp-27")

      {:ok, container} = TestcontainerEx.start_container(config)

  ## With Erlang distribution enabled

      config =
        ElixirContainer.new()
        |> ElixirContainer.with_cookie("my-secret-cookie")
        |> ElixirContainer.with_node_name("app@192.168.1.100")
        |> ElixirContainer.with_distribution_port(9100)

      {:ok, container} = TestcontainerEx.start_container(config)

  ## Mount a local Mix project

      config =
        ElixirContainer.new()
        |> ElixirContainer.with_project("/path/to/my_app")

      {:ok, container} = TestcontainerEx.start_container(config)

  ## Connect from your host machine

  After the container starts, the Erlang distribution port and EPMD port are
  exposed. From your local IEx session:

      Node.connect(:"app@<host>")
      Node.list()  # => [:"app@<host>"]

  ## Copy a module into a running container and call it remotely

      ElixirContainer.copy_module(container, MyModule, conn)
      :rpc.call(:"app@<host>", MyModule, :hello, [])

  ## Run a release with remote shell

      config =
        ElixirContainer.new()
        |> ElixirContainer.with_image("my_app:latest")
        |> ElixirContainer.with_release("my_app")
        |> ElixirContainer.with_cookie("release-cookie")

      {:ok, container} = TestcontainerEx.start_container(config)
  """

  alias TestcontainerEx.{
    Container.Builder,
    Container.Config,
    Engine,
    ElixirContainer,
    LogWaitStrategy,
    PortWaitStrategy
  }

  import TestcontainerEx.Container.Config, only: [is_valid_image: 1]

  @default_image "elixir"
  @default_tag "latest"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_epmd_port 4369
  @default_dist_port 9100
  @default_wait_timeout 120_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :wait_timeout]
  defstruct [
    :image,
    :wait_timeout,
    :cookie,
    :node_name,
    :dist_port,
    :project_path,
    :release_name,
    :release_args,
    :vm_args,
    :env_vars,
    :cmd,
    :working_dir,
    :name,
    check_image: @default_image,
    reuse: false
  ]

  # ── Constructor ────────────────────────────────────────────────────

  @doc """
  Creates a new `ElixirContainer` with default configuration.

  Defaults:
  - Image: `elixir:latest`
  - Wait timeout: 120s
  - No distribution (cookie/node_name not set)
  - No project mounted
  """
  @spec new() :: t()
  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      wait_timeout: @default_wait_timeout,
      cookie: nil,
      node_name: nil,
      dist_port: nil,
      project_path: nil,
      release_name: nil,
      release_args: [],
      vm_args: [],
      env_vars: %{},
      cmd: nil,
      working_dir: nil
    }

  # ── Setters ────────────────────────────────────────────────────────

  @doc """
  Sets the container image (e.g. `"elixir:1.17-otp-27"` or a custom image
  with Elixir/OTP pre-installed).
  """
  @spec with_image(t(), String.t()) :: t()
  def with_image(%__MODULE__{} = config, image) when is_binary(image) do
    %{config | image: image}
  end

  @doc """
  Sets the wait timeout in milliseconds.
  """
  @spec with_wait_timeout(t(), pos_integer()) :: t()
  def with_wait_timeout(%__MODULE__{} = config, timeout)
      when is_integer(timeout) and timeout > 0 do
    %{config | wait_timeout: timeout}
  end

  @doc """
  Sets the Erlang distribution cookie.

  Required for node-to-node communication. Both nodes must use the same cookie.

      config
      |> ElixirContainer.with_cookie("my-secret-cookie")
  """
  @spec with_cookie(t(), String.t()) :: t()
  def with_cookie(%__MODULE__{} = config, cookie) when is_binary(cookie) do
    %{config | cookie: cookie}
  end

  @doc """
  Sets the Erlang node name for distribution.

  Use long names (`--name`) for cross-machine connections, short names
  (`--sname`) for same-network connections.

      config
      |> ElixirContainer.with_node_name("app@192.168.1.100")

  When set, EPMD port 4369 and the distribution port are automatically exposed.
  """
  @spec with_node_name(t(), String.t()) :: t()
  def with_node_name(%__MODULE__{} = config, node_name) when is_binary(node_name) do
    %{config | node_name: node_name}
  end

  @doc """
  Sets the fixed Erlang distribution port (default: 9100).

  Erlang uses a random port by default, which is difficult with containers.
  Setting a fixed port makes it possible to expose it through Docker.

      config
      |> ElixirContainer.with_distribution_port(9100)
  """
  @spec with_distribution_port(t(), pos_integer()) :: t()
  def with_distribution_port(%__MODULE__{} = config, port) when is_integer(port) and port > 0 do
    %{config | dist_port: port}
  end

  @doc """
  Bind-mounts a local Mix project directory into the container.

  The project is mounted at `/app` inside the container. Useful for running
  tests, starting a remote IEx session, or deploying code.

      config
      |> ElixirContainer.with_project("/path/to/my_app")
  """
  @spec with_project(t(), String.t()) :: t()
  def with_project(%__MODULE__{} = config, path) when is_binary(path) do
    %{config | project_path: path, working_dir: "/app"}
  end

  @doc """
  Configures the container to run a release.

  When set, the container starts the release instead of an IEx session.
  The release binary is expected to be at `/app/bin/<release_name>`.

      config
      |> ElixirContainer.with_release("my_app")
      |> ElixirContainer.with_release_args(["start"])
  """
  @spec with_release(t(), String.t()) :: t()
  def with_release(%__MODULE__{} = config, name) when is_binary(name) do
    %{config | release_name: name}
  end

  @doc """
  Sets the arguments passed to the release binary (default: `["start"]`).

      config
      |> ElixirContainer.with_release_args(["start_iex"])
  """
  @spec with_release_args(t(), [String.t()]) :: t()
  def with_release_args(%__MODULE__{} = config, args) when is_list(args) do
    %{config | release_args: args}
  end

  @doc """
  Sets additional `vm.args` entries for the Erlang VM.

  These are appended to the generated vm.args file inside the container.
  Useful for tuning distribution, heart, or other kernel settings.

      config
      |> ElixirContainer.with_vm_args([
        "-kernel inet_dist_listen_min 9100",
        "-kernel inet_dist_listen_max 9100"
      ])
  """
  @spec with_vm_args(t(), [String.t()]) :: t()
  def with_vm_args(%__MODULE__{} = config, args) when is_list(args) do
    %{config | vm_args: args}
  end

  @doc """
  Sets environment variables inside the container.

  These are merged with any distribution-related env vars set automatically.

      config
      |> ElixirContainer.with_env_vars(%{
        "MIX_ENV" => "prod",
        "DATABASE_URL" => "postgres://..."
      })
  """
  @spec with_env_vars(t(), map()) :: t()
  def with_env_vars(%__MODULE__{} = config, vars) when is_map(vars) do
    %{config | env_vars: Map.merge(config.env_vars, vars)}
  end

  @doc """
  Sets a custom command to run inside the container.

  Overrides the default IEx or release command. Useful for running
  custom scripts or one-off commands.

      config
      |> ElixirContainer.with_cmd(["mix", "test"])
  """
  @spec with_cmd(t(), [String.t()]) :: t()
  def with_cmd(%__MODULE__{} = config, cmd) when is_list(cmd) do
    %{config | cmd: cmd}
  end

  @doc """
  Sets the check image regex used to validate the image name.
  """
  @spec with_check_image(t(), String.t() | Regex.t()) :: t()
  def with_check_image(%__MODULE__{} = config, check_image) when is_valid_image(check_image) do
    %__MODULE__{config | check_image: check_image}
  end

  @doc """
  Enables or disables container reuse.
  """
  @spec with_reuse(t(), boolean()) :: t()
  def with_reuse(%__MODULE__{} = config, reuse) when is_boolean(reuse) do
    %__MODULE__{config | reuse: reuse}
  end

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  # ── Accessors ──────────────────────────────────────────────────────

  @doc "Returns the default image name without tag."
  @spec default_image() :: String.t()
  def default_image, do: @default_image

  @doc "Returns the default EPMD port (4369)."
  @spec epmd_port() :: 4369
  def epmd_port, do: @default_epmd_port

  @doc "Returns the default distribution port (9100)."
  @spec default_dist_port() :: 9100
  def default_dist_port, do: @default_dist_port

  @doc """
  Returns the mapped EPMD port on the host machine.
  """
  @spec mapped_epmd_port(Config.t()) :: integer() | nil
  def mapped_epmd_port(%Config{} = container),
    do: TestcontainerEx.get_port(container, @default_epmd_port)

  @doc """
  Returns the mapped distribution port on the host machine.
  """
  @spec mapped_dist_port(Config.t()) :: integer() | nil
  def mapped_dist_port(%Config{} = container) do
    dist_port = container.environment["ELIXIR_DIST_PORT"] || "#{@default_dist_port}"
    TestcontainerEx.get_port(container, String.to_integer(dist_port))
  end

  @doc """
  Returns the full node name for connecting from the host.

  Returns `nil` if no node_name is configured.

      node_str = ElixirContainer.connection_node(container)
      # => "app@localhost:9100"
      Node.connect(String.to_atom(node_str))
  """
  @spec connection_node(Config.t()) :: String.t() | nil
  def connection_node(%Config{} = container) do
    case container.environment["RELEASE_NODE"] do
      nil ->
        nil

      node_name ->
        host = TestcontainerEx.get_host(container)
        node_part = node_name |> String.split("@") |> List.first()
        dist_port = mapped_dist_port(container)
        "#{node_part}@#{host}:#{dist_port}"
    end
  end

  # ── Remote operations ──────────────────────────────────────────────

  @doc """
  Connects from the host to the container's Erlang node.

  Requires the container to have been started with `with_node_name/2`
  and `with_cookie/2`.

      {:ok, container} = TestcontainerEx.start_container(
        ElixirContainer.new()
        |> ElixirContainer.with_cookie("secret")
        |> ElixirContainer.with_node_name("app@192.168.1.100")
      )

      ElixirContainer.connect(container, conn)
      # => true
  """
  @spec connect(Config.t(), Req.Request.t()) :: boolean()
  def connect(%Config{} = container, _conn) do
    case connection_node(container) do
      nil -> false
      node_str -> Node.connect(String.to_atom(node_str))
    end
  end

  @doc """
  Copies an Elixir module's source file into the container.

  The module is compiled inside the container and can then be called
  via `:rpc.call/4`.

      ElixirContainer.copy_module(container, MyApp.Helper, conn)

      :rpc.call(:"app@localhost:9100", MyApp.Helper, :hello, [])
      # => :world

  The source file is expected to be at `lib/<module_path>.ex` relative
  to the project root, or at the given `source_path`.
  """
  @spec copy_module(Config.t(), module(), Req.Request.t(), String.t() | nil) ::
          :ok | {:error, term()}
  def copy_module(%Config{} = container, module, conn, source_path \\ nil) do
    source_path = source_path || default_source_path(module)

    case File.read(source_path) do
      {:ok, contents} ->
        Engine.Api.put_file(
          container.container_id,
          conn,
          "/app/lib",
          "#{module_path(module)}.ex",
          contents
        )

      {:error, reason} ->
        {:error, {:file_not_found, source_path, reason}}
    end
  end

  @doc """
  Evaluates code inside the container's Erlang node via RPC.

      ElixirContainer.remote_eval(container, conn, "IO.puts(:hello)")
      # => "hello"
  """
  @spec remote_eval(Config.t(), Req.Request.t(), String.t()) ::
          {:ok, term()} | {:error, term()}
  def remote_eval(%Config{} = container, conn, code) do
    case connection_node(container) do
      nil ->
        {:error, :no_node_name}

      node_str ->
        _node = String.to_atom(node_str)

        case Engine.Api.start_exec(
               container.container_id,
               [
                 "iex",
                 "--eval",
                 code
               ],
               conn
             ) do
          {:ok, exec_id} ->
            wait_for_exec(exec_id, container, conn)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Runs a Mix task inside the container.

      ElixirContainer.run_mix(container, conn, "test")
      ElixirContainer.run_mix(container, conn, "ecto.migrate")
  """
  @spec run_mix(Config.t(), Req.Request.t(), String.t()) :: :ok | {:error, term()}
  def run_mix(%Config{} = container, conn, task) do
    case Engine.Api.start_exec(container.container_id, ["mix", task], conn) do
      {:ok, exec_id} ->
        wait_for_exec(exec_id, container, conn)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Builder protocol ───────────────────────────────────────────────

  defimpl Builder do
    @impl true
    @spec build(ElixirContainer.t()) :: Config.t()
    def build(%ElixirContainer{} = config) do
      # Build the base container config
      container =
        config.image
        |> Config.new()
        |> maybe_with_distribution(config)
        |> maybe_with_project(config)
        |> maybe_with_env_vars(config)
        |> maybe_with_working_dir(config)
        |> maybe_with_cmd(config)
        |> Config.with_check_image(config.check_image)
        |> Config.with_reuse(config.reuse)
        |> then(fn cfg ->
          if config.name, do: Config.with_name(cfg, config.name), else: cfg
        end)

      # Choose wait strategy based on configuration
      container =
        if config.release_name do
          # For releases, wait for the application to be started
          container
          |> Config.with_waiting_strategy(
            LogWaitStrategy.new(
              ~r/.*Running.*with.*/,
              config.wait_timeout,
              1000
            )
          )
        else
          # For IEx sessions, wait for the IEx prompt
          container
          |> Config.with_waiting_strategy(
            LogWaitStrategy.new(
              ~r/.*iex\(\d+\)>.*/,
              config.wait_timeout,
              1000
            )
          )
        end

      # Add port wait strategy for distribution if configured
      container =
        if config.node_name && config.dist_port do
          Config.with_waiting_strategy(
            container,
            PortWaitStrategy.new("localhost", config.dist_port, config.wait_timeout, 1000)
          )
        else
          container
        end

      Config.valid_image!(container)
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok

    # ── Distribution setup ────────────────────────────────────────────

    defp maybe_with_distribution(container, %{node_name: nil}), do: container

    defp maybe_with_distribution(container, config) do
      dist_port = config.dist_port || ElixirContainer.default_dist_port()

      container
      # Expose EPMD and distribution ports
      |> Config.with_exposed_ports([ElixirContainer.epmd_port(), dist_port])
      # Set distribution environment variables
      |> Config.with_environment("RELEASE_DISTRIBUTION", "name")
      |> Config.with_environment("RELEASE_NODE", config.node_name)
      |> Config.with_environment("RELEASE_COOKIE", config.cookie || "default-cookie")
      |> Config.with_environment("ELIXIR_DIST_PORT", to_string(dist_port))
    end

    # ── Project mount ─────────────────────────────────────────────────

    defp maybe_with_project(container, %{project_path: nil}), do: container

    defp maybe_with_project(container, %{project_path: path}) do
      Config.with_bind_mount(container, path, "/app", "rw")
    end

    # ── Environment variables ─────────────────────────────────────────

    defp maybe_with_env_vars(container, %{env_vars: vars}) when map_size(vars) == 0, do: container

    defp maybe_with_env_vars(container, %{env_vars: vars}) do
      Enum.reduce(vars, container, fn {key, value}, acc ->
        Config.with_environment(acc, key, value)
      end)
    end

    # ── Working directory ────────────────────────────────────────────

    defp maybe_with_working_dir(container, %{working_dir: nil}), do: container

    defp maybe_with_working_dir(container, %{working_dir: dir} = config) do
      Config.with_cmd(container, ["sh", "-c", "cd #{dir} && #{default_cmd(config)}"])
    end

    # ── Command ──────────────────────────────────────────────────────

    defp maybe_with_cmd(container, %{cmd: nil}), do: container

    defp maybe_with_cmd(container, %{cmd: cmd}) do
      Config.with_cmd(container, cmd)
    end

    # ── Default command ──────────────────────────────────────────────

    defp default_cmd(%{release_name: name, release_args: args}) when not is_nil(name) do
      "/app/bin/#{name} #{Enum.join(args, " ")}"
    end

    defp default_cmd(%{node_name: nil}) do
      "iex"
    end

    defp default_cmd(%{node_name: node_name, dist_port: dist_port, vm_args: vm_args}) do
      dist_port_str =
        if dist_port,
          do: to_string(dist_port),
          else: to_string(ElixirContainer.default_dist_port())

      vm_args_str = if vm_args == [], do: "", else: Enum.join(vm_args, " ")

      "iex --name #{node_name} --cookie #{System.get_env("RELEASE_COOKIE", "default-cookie")} -kernel inet_dist_listen_min #{dist_port_str} -kernel inet_dist_listen_max #{dist_port_str} #{vm_args_str}"
    end
  end

  # ── Private helpers ───────────────────────────────────────────────

  defp default_source_path(module) do
    module_str = Atom.to_string(module)
    path_parts = String.split(module_str, ".")
    file_name = List.last(path_parts) |> Macro.underscore()
    dir_path = Enum.drop(path_parts, -1) |> Enum.map(&Macro.underscore/1)
    Path.join(["lib" | dir_path] ++ ["#{file_name}.ex"])
  end

  defp module_path(module) do
    module_str = Atom.to_string(module)
    path_parts = String.split(module_str, ".")
    file_name = List.last(path_parts) |> Macro.underscore()
    dir_path = Enum.drop(path_parts, -1) |> Enum.map(&Macro.underscore/1)
    Path.join(dir_path ++ [file_name])
  end

  defp wait_for_exec(exec_id, container, conn) do
    case Engine.Api.inspect_exec(exec_id, conn) do
      {:ok, %{running: true}} ->
        Process.sleep(100)
        wait_for_exec(exec_id, container, conn)

      {:ok, %{running: false, exit_code: 0}} ->
        :ok

      {:ok, %{running: false, exit_code: code}} ->
        {:error, {:exec_failed, code}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
