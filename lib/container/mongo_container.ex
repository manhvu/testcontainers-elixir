# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.MongoContainer do
  @behaviour TestcontainerEx.DatabaseBehaviour
  @moduledoc """
  Provides functionality for creating and managing Mongo container configurations.
  """

  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.MongoContainer

  use TestcontainerEx.ContainerConfig

  @default_image "mongo"
  @default_tag "latest"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_user "test"
  @default_password "test"
  @default_database "test"
  @default_port 27_017
  @default_wait_timeout 180_000

  @type t :: %__MODULE__{}

  @enforce_keys [:image, :user, :password, :database, :port, :wait_timeout, :persistent_volume]
  defstruct [
    :image,
    :user,
    :password,
    :database,
    :port,
    :wait_timeout,
    :persistent_volume,
    :name,
    check_image: @default_image,
    reuse: false
  ]

  def new,
    do: %__MODULE__{
      image: @default_image_with_tag,
      user: @default_user,
      password: @default_password,
      database: @default_database,
      port: @default_port,
      wait_timeout: @default_wait_timeout,
      persistent_volume: nil
    }

  def with_image(%__MODULE__{} = config, image) when is_binary(image),
    do: %{config | image: image}

  def with_username(%__MODULE__{} = config, username) when is_binary(username),
    do: with_user(config, username)

  def with_user(%__MODULE__{} = config, user) when is_binary(user), do: %{config | user: user}

  def with_password(%__MODULE__{} = config, password) when is_binary(password),
    do: %{config | password: password}

  def with_database(%__MODULE__{} = config, database) when is_binary(database),
    do: %{config | database: database}

  def with_port(%__MODULE__{} = config, port) when is_integer(port) or is_tuple(port),
    do: %{config | port: port}

  def with_persistent_volume(%__MODULE__{} = config, volume) when is_binary(volume),
    do: %{config | persistent_volume: volume}

  def with_wait_timeout(%__MODULE__{} = config, timeout) when is_integer(timeout),
    do: %{config | wait_timeout: timeout}

  @doc """
  Sets the container name.
  """
  @spec with_name(t(), String.t()) :: t()
  def with_name(%__MODULE__{} = config, name) when is_binary(name) do
    %__MODULE__{config | name: name}
  end

  def default_port, do: @default_port
  def default_image, do: @default_image
  def default_image_with_tag, do: @default_image <> ":" <> @default_tag

  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_port)

  def connection_parameters(%Config{} = container) do
    [
      hostname: TestcontainerEx.get_host(container),
      port: port(container),
      username: container.environment[:MONGO_INITDB_ROOT_USERNAME],
      password: container.environment[:MONGO_INITDB_ROOT_PASSWORD],
      database: container.environment[:MONGO_INITDB_DATABASE]
    ]
  end

  def mongo_url(%Config{} = container, opts \\ []) when is_list(opts) do
    protocol = Keyword.get(opts, :protocol, "mongodb")
    username = Keyword.get(opts, :username, container.environment[:MONGO_INITDB_ROOT_USERNAME])
    password = Keyword.get(opts, :password, container.environment[:MONGO_INITDB_ROOT_PASSWORD])
    database = Keyword.get(opts, :database, container.environment[:MONGO_INITDB_DATABASE])
    query_string = opts |> Keyword.get(:options, []) |> encode_query_string()

    "#{protocol}://#{username}:#{password}@#{TestcontainerEx.get_host(container)}:#{port(container)}/#{database}#{query_string}"
  end

  def database_url(%Config{} = container, opts \\ []), do: mongo_url(container, opts)

  defimpl Builder do
    @spec build(MongoContainer.t()) :: Config.t()
    @impl true
    def build(%MongoContainer{} = config) do
      Config.new(config.image)
      |> then(MongoContainer.container_port_fun(config.port))
      |> Config.with_environment(:MONGO_INITDB_ROOT_USERNAME, config.user)
      |> Config.with_environment(:MONGO_INITDB_ROOT_PASSWORD, config.password)
      |> Config.with_environment(:MONGO_INITDB_DATABASE, config.database)
      |> then(MongoContainer.container_volume_fun(config.persistent_volume))
      |> Config.with_waiting_strategy(
        CommandWaitStrategy.new(
          [
            "sh",
            "-c",
            "mongosh --eval \"db.adminCommand('ping')\" || mongo --eval \"db.adminCommand('ping')\""
          ],
          config.wait_timeout
        )
      )
      |> Config.with_check_image(config.check_image)
      |> Config.with_reuse(config.reuse)
      |> then(fn cfg ->
        if config.name, do: Config.with_name(cfg, config.name), else: cfg
      end)
      |> Config.valid_image!()
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end

  @doc false
  def container_port_fun(nil), do: &Function.identity/1

  def container_port_fun({exposed_port, host_port}) do
    fn container -> Config.with_fixed_port(container, exposed_port, host_port) end
  end

  def container_port_fun(port) do
    fn container -> Config.with_exposed_port(container, port) end
  end

  @doc false
  def container_volume_fun(nil), do: &Function.identity/1

  def container_volume_fun(volume) when is_binary(volume) do
    fn container -> Config.with_bind_volume(container, volume, "/data/db") end
  end

  defp encode_query_string(options) when options in [nil, [], %{}], do: ""

  defp encode_query_string(options) when is_map(options) or is_list(options) do
    case URI.encode_query(options) do
      "" -> ""
      query -> "?" <> query
    end
  end
end
