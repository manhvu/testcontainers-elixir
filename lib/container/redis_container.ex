# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.RedisContainer do
  @moduledoc """
  Provides functionality for creating and managing Redis container configurations.
  """

  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.RedisContainer

  use TestcontainerEx.ContainerConfig

  @default_image "redis"
  @default_tag "7.2-alpine"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_port 6379
  @default_wait_timeout 60_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :port, :wait_timeout]
  defstruct [
    :image,
    :port,
    :wait_timeout,
    :name,
    check_image: @default_image,
    reuse: false,
    password: nil
  ]

  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      wait_timeout: @default_wait_timeout,
      port: @default_port,
      password: nil
    }

  def with_image(%__MODULE__{} = config, image) when is_binary(image) do
    %{config | image: image}
  end

  def with_port(%__MODULE__{} = config, port) when is_integer(port) do
    %{config | port: port}
  end

  def with_password(%__MODULE__{} = config, password) when is_binary(password) do
    %{config | password: password}
  end

  def with_wait_timeout(%__MODULE__{} = config, wait_timeout) when is_integer(wait_timeout) do
    %{config | wait_timeout: wait_timeout}
  end

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  def default_image, do: @default_image

  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_port)

  def connection_url(%Config{} = container) do
    password = container.environment[:REDIS_PASSWORD]
    auth_part = if password, do: ":#{password}@", else: ""
    "redis://#{auth_part}#{TestcontainerEx.get_host(container)}:#{port(container)}/"
  end

  defimpl Builder do
    @spec build(RedisContainer.t()) :: Config.t()
    @impl true
    def build(%RedisContainer{} = config) do
      container =
        Config.new(config.image)
        |> Config.with_exposed_port(config.port)
        |> Config.with_check_image(config.check_image)
        |> Config.with_reuse(config.reuse)
        |> then(fn cfg ->
          if config.name, do: Config.with_name(cfg, config.name), else: cfg
        end)

      container =
        if config.password do
          container
          |> Config.with_cmd(["redis-server", "--requirepass", config.password])
          |> Config.with_waiting_strategy(
            CommandWaitStrategy.new(
              ["redis-cli", "-a", config.password, "PING"],
              config.wait_timeout
            )
          )
          |> Config.with_environment("REDIS_PASSWORD", config.password)
        else
          container
          |> Config.with_waiting_strategy(
            CommandWaitStrategy.new(["redis-cli", "PING"], config.wait_timeout)
          )
        end

      Config.valid_image!(container)
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end
end
