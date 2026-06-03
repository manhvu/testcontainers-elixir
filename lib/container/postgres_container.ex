# SPDX-License-Identifier: MIT
defmodule TestcontainerEx.PostgresContainer do
  @behaviour TestcontainerEx.DatabaseBehaviour
  @moduledoc """
  Provides functionality for creating and managing Postgres container configurations.
  """

  alias TestcontainerEx.CommandWaitStrategy
  alias TestcontainerEx.Container.Builder
  alias TestcontainerEx.Container.Config
  alias TestcontainerEx.PostgresContainer

  import TestcontainerEx.Container.Config, only: [is_valid_image: 1]

  @default_image "postgres"
  @default_tag "15-alpine"
  @default_image_with_tag "#{@default_image}:#{@default_tag}"
  @default_user "test"
  @default_password "test"
  @default_database "test"
  @default_port 5432
  @default_wait_timeout 60_000

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

  def with_image(%__MODULE__{} = c, image) when is_binary(image), do: %{c | image: image}
  def with_user(%__MODULE__{} = c, user) when is_binary(user), do: %{c | user: user}
  def with_password(%__MODULE__{} = c, pw) when is_binary(pw), do: %{c | password: pw}
  def with_database(%__MODULE__{} = c, db) when is_binary(db), do: %{c | database: db}

  def with_port(%__MODULE__{} = c, port) when is_integer(port) or is_tuple(port),
    do: %{c | port: port}

  def with_persistent_volume(%__MODULE__{} = c, vol) when is_binary(vol),
    do: %{c | persistent_volume: vol}

  def with_wait_timeout(%__MODULE__{} = c, t) when is_integer(t), do: %{c | wait_timeout: t}

  def with_check_image(%__MODULE__{} = c, ci) when is_valid_image(ci),
    do: %__MODULE__{c | check_image: ci}

  def with_reuse(%__MODULE__{} = c, reuse) when is_boolean(reuse),
    do: %__MODULE__{c | reuse: reuse}

  def default_port, do: @default_port
  def default_image, do: @default_image
  def default_image_with_tag, do: @default_image <> ":" <> @default_tag

  def port(%Config{} = container), do: TestcontainerEx.get_port(container, @default_port)

  def connection_parameters(%Config{} = container) do
    [
      hostname: TestcontainerEx.get_host(container),
      port: port(container),
      username: container.environment[:POSTGRES_USER],
      password: container.environment[:POSTGRES_PASSWORD],
      database: container.environment[:POSTGRES_DB]
    ]
  end

  defimpl Builder do
    @spec build(PostgresContainer.t()) :: Config.t()
    @impl true
    def build(%PostgresContainer{} = config) do
      Config.new(config.image)
      |> then(PostgresContainer.container_port_fun(config.port))
      |> Config.with_environment(:POSTGRES_USER, config.user)
      |> Config.with_environment(:POSTGRES_PASSWORD, config.password)
      |> Config.with_environment(:POSTGRES_DB, config.database)
      |> then(PostgresContainer.container_volume_fun(config.persistent_volume))
      |> Config.with_waiting_strategy(
        CommandWaitStrategy.new(
          ["sh", "-c", "pg_isready -U #{config.user} -d #{config.database} -h localhost"],
          config.wait_timeout
        )
      )
      |> Config.with_check_image(config.check_image)
      |> Config.with_reuse(config.reuse)
      |> Config.valid_image!()
    end

    @impl true
    def after_start(_config, _container, _conn), do: :ok
  end

  @doc false
  def container_port_fun(nil), do: &Function.identity/1

  def container_port_fun({exposed, host}),
    do: fn c -> Config.with_fixed_port(c, exposed, host) end

  def container_port_fun(port), do: fn c -> Config.with_exposed_port(c, port) end

  @doc false
  def container_volume_fun(nil), do: &Function.identity/1

  def container_volume_fun(vol) when is_binary(vol),
    do: fn c -> Config.with_bind_volume(c, vol, "/var/lib/postgresql/data") end
end
