defmodule TestcontainerEx.RabbitMQContainer do
  @moduledoc """
  Provides functionality for creating and managing RabbitMQ container configurations.
  """

  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.RabbitMQContainer

  use TestcontainerEx.ContainerConfig

  @default_image "rabbitmq"
  @default_tag "3-alpine"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_port 5672
  @default_username "guest"
  @default_password "guest"
  @default_virtual_host "/"
  @default_command ["sh", "-c", "chmod 400 /var/lib/rabbitmq/.erlang.cookie; rabbitmq-server"]
  @default_wait_timeout 60_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :port, :wait_timeout]
  defstruct [
    :image,
    :port,
    :username,
    :password,
    :virtual_host,
    :cmd,
    :wait_timeout,
    :name,
    check_image: @default_image,
    reuse: false,
    force_reuse: false
  ]

  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      port: @default_port,
      username: @default_username,
      password: @default_password,
      virtual_host: @default_virtual_host,
      cmd: @default_command,
      wait_timeout: @default_wait_timeout
    }

  def with_image(%__MODULE__{} = c, image), do: %{c | image: image}
  def with_port(%__MODULE__{} = c, port) when is_integer(port), do: %{c | port: port}
  def with_wait_timeout(%__MODULE__{} = c, t) when is_integer(t), do: %{c | wait_timeout: t}
  def with_username(%__MODULE__{} = c, u) when is_binary(u), do: %{c | username: u}
  def with_password(%__MODULE__{} = c, p) when is_binary(p), do: %{c | password: p}
  def with_virtual_host(%__MODULE__{} = c, v) when is_binary(v), do: %{c | virtual_host: v}
  def with_cmd(%__MODULE__{} = c, cmd) when is_list(cmd), do: %{c | cmd: cmd}

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  def with_force_reuse(%__MODULE__{} = c), do: %__MODULE__{c | reuse: true, force_reuse: true}

  def default_image, do: @default_image
  def default_port, do: @default_port
  def default_image_with_tag, do: @default_image <> ":" <> @default_tag

  def port(%Config{} = container) do
    port_number =
      case container.environment[:RABBITMQ_NODE_PORT] do
        nil -> @default_port
        port_str -> String.to_integer(port_str)
      end

    TestcontainerEx.get_port(container, port_number)
  end

  def connection_url(%Config{} = container) do
    port_number =
      case container.environment[:RABBITMQ_NODE_PORT] do
        nil -> @default_port
        port_str -> String.to_integer(port_str)
      end

    mapped_port = Config.mapped_port(container, port_number)

    "amqp://#{container.environment[:RABBITMQ_DEFAULT_USER]}:#{container.environment[:RABBITMQ_DEFAULT_PASS]}@#{TestcontainerEx.get_host(container)}:#{mapped_port}#{virtual_host_segment(container)}"
  end

  def connection_parameters(%Config{} = container) do
    [
      host: TestcontainerEx.get_host(container),
      port: port(container),
      username: container.environment[:RABBITMQ_DEFAULT_USER],
      password: container.environment[:RABBITMQ_DEFAULT_PASS],
      virtual_host: container.environment[:RABBITMQ_DEFAULT_VHOST]
    ]
  end

  defp virtual_host_segment(container) do
    container.environment[:RABBITMQ_DEFAULT_VHOST] || "/"
  end

  defimpl Builder do
    @impl true
    @spec build(RabbitMQContainer.t()) :: Config.t()
    def build(%RabbitMQContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_port(config.port)
      |> Config.with_environment(:RABBITMQ_DEFAULT_USER, config.username)
      |> Config.with_environment(:RABBITMQ_DEFAULT_PASS, config.password)
      |> Config.with_environment(:RABBITMQ_DEFAULT_VHOST, config.virtual_host)
      |> Config.with_environment(:RABBITMQ_NODE_PORT, to_string(config.port))
      |> Config.with_cmd(config.cmd)
      |> Config.with_waiting_strategy(
        CommandWaitStrategy.new(["rabbitmq-diagnostics", "check_running"], config.wait_timeout)
      )
      |> Config.with_check_image(config.check_image)
      |> Config.with_reuse(config.reuse)
      |> then(fn c -> if config.force_reuse, do: Config.with_force_reuse(c, true), else: c end)
      |> then(fn cfg ->
        if config.name, do: Config.with_name(cfg, config.name), else: cfg
      end)
      |> Config.valid_image!()
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
