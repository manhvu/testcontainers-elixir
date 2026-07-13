# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.ClickHouseContainer do
  @behaviour TestcontainerEx.DatabaseBehaviour
  @moduledoc """
  Provides functionality for creating and managing ClickHouse container configurations.

  Exposes both the HTTP interface (port 8123) and the native TCP interface
  (port 9000). The HTTP interface is used by the default wait strategy and is
  the most common entry point for Elixir drivers such as `Clickhousex`.
  """

  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.ClickHouseContainer

  use TestcontainerEx.ContainerConfig

  @default_image "clickhouse/clickhouse-server"
  @default_tag "latest"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_user "default"
  @default_password "default"
  @default_database "default"
  @default_http_port 8123
  @default_native_port 9000
  @default_wait_timeout 120_000

  @type t :: %__MODULE__{}

  @enforce_keys [
    :image,
    :user,
    :password,
    :database,
    :http_port,
    :native_port,
    :wait_timeout,
    :persistent_volume
  ]
  defstruct [
    :image,
    :user,
    :password,
    :database,
    :http_port,
    :native_port,
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
      http_port: @default_http_port,
      native_port: @default_native_port,
      wait_timeout: @default_wait_timeout,
      persistent_volume: nil
    }

  def with_image(%__MODULE__{} = c, image) when is_binary(image), do: %{c | image: image}
  def with_user(%__MODULE__{} = c, user) when is_binary(user), do: %{c | user: user}
  def with_password(%__MODULE__{} = c, pw) when is_binary(pw), do: %{c | password: pw}
  def with_database(%__MODULE__{} = c, db) when is_binary(db), do: %{c | database: db}

  def with_http_port(%__MODULE__{} = c, port) when is_integer(port), do: %{c | http_port: port}

  def with_native_port(%__MODULE__{} = c, port) when is_integer(port),
    do: %{c | native_port: port}

  def with_port(%__MODULE__{} = c, {http_port, native_port})
      when is_integer(http_port) and is_integer(native_port),
      do: %{c | http_port: http_port, native_port: native_port}

  def with_persistent_volume(%__MODULE__{} = c, vol) when is_binary(vol),
    do: %{c | persistent_volume: vol}

  def with_wait_timeout(%__MODULE__{} = c, t) when is_integer(t), do: %{c | wait_timeout: t}

  def default_http_port, do: @default_http_port
  def default_native_port, do: @default_native_port

  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_http_port)

  def http_port(%Config{} = container),
    do: TestcontainerEx.get_port(container, @default_http_port)

  def native_port(%Config{} = container),
    do: TestcontainerEx.get_port(container, @default_native_port)

  def connection_parameters(%Config{} = container) do
    [
      hostname: TestcontainerEx.get_host(container),
      port: http_port(container),
      scheme: "http",
      user: container.environment[:CLICKHOUSE_USER],
      password: container.environment[:CLICKHOUSE_PASSWORD],
      database: container.environment[:CLICKHOUSE_DB]
    ]
  end

  def connection_url(%Config{} = container, opts \\ []) when is_list(opts) do
    protocol = Keyword.get(opts, :protocol, "http")
    user = Keyword.get(opts, :user, container.environment[:CLICKHOUSE_USER])
    password = Keyword.get(opts, :password, container.environment[:CLICKHOUSE_PASSWORD])
    database = Keyword.get(opts, :database, container.environment[:CLICKHOUSE_DB])
    port = Keyword.get(opts, :port, http_port(container))
    host = Keyword.get(opts, :host, TestcontainerEx.get_host(container))

    auth_part =
      if user do
        pw = if password, do: ":#{password}", else: ""
        "#{user}#{pw}@"
      else
        ""
      end

    "#{protocol}://#{auth_part}#{host}:#{port}/?database=#{database}"
  end

  defimpl Builder do
    @spec build(ClickHouseContainer.t()) :: Config.t()
    @impl true
    def build(%ClickHouseContainer{} = config) do
      Config.new(config.image)
      |> Config.with_exposed_ports([config.http_port, config.native_port])
      |> Config.with_environment(:CLICKHOUSE_DB, config.database)
      |> Config.with_environment(:CLICKHOUSE_USER, config.user)
      |> Config.with_environment(:CLICKHOUSE_PASSWORD, config.password)
      |> Config.with_environment(:CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT, "1")
      |> then(ClickHouseContainer.container_volume_fun(config.persistent_volume))
      |> Config.with_waiting_strategy(
        CommandWaitStrategy.new(
          [
            "clickhouse-client",
            "--port",
            to_string(config.http_port),
            "--user",
            config.user,
            "--password",
            config.password,
            "--query",
            "SELECT 1"
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
  def container_volume_fun(nil), do: &Function.identity/1

  def container_volume_fun(volume) when is_binary(volume) do
    fn container -> Config.with_bind_volume(container, volume, "/var/lib/clickhouse") end
  end
end
